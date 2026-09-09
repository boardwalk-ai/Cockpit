package ingest

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"github.com/octopilot/cockpit-go/internal/config"
	"github.com/octopilot/cockpit-go/internal/embedclient"
	"github.com/octopilot/cockpit-go/internal/extract"
	"github.com/redis/go-redis/v9"
)

const Queue = "cockpit:ingest"

type Job struct {
	JobID      uuid.UUID `json:"job_id"`
	DocumentID uuid.UUID `json:"document_id"`
}

type Worker struct {
	cfg    config.Config
	cockpit *pgxpool.Pool
	vector  *pgxpool.Pool
	rdb    *redis.Client
	minio  *minio.Client
	embed  *embedclient.Client
	hirara *extract.Hirara
}

func New(cfg config.Config, cockpit, vector *pgxpool.Pool, rdb *redis.Client) (*Worker, error) {
	mc, err := minio.New(cfg.MinioEndpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.MinioAccess, cfg.MinioSecret, ""),
		Secure: cfg.MinioSecure,
	})
	if err != nil {
		return nil, err
	}
	return &Worker{
		cfg:     cfg,
		cockpit: cockpit,
		vector:  vector,
		rdb:     rdb,
		minio:   mc,
		embed:   embedclient.New(cfg.EmbedURL),
		hirara:  extract.NewHirara(cfg.HiraraURL, cfg.HiraraToken),
	}, nil
}

func Enqueue(ctx context.Context, rdb *redis.Client, job Job) error {
	b, _ := json.Marshal(job)
	return rdb.RPush(ctx, Queue, b).Err()
}

func (w *Worker) Run(ctx context.Context) error {
	log.Println("ingest worker listening on", Queue)
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		res, err := w.rdb.BLPop(ctx, 5*time.Second, Queue).Result()
		if err == redis.Nil {
			continue
		}
		if err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			log.Println("blpop", err)
			time.Sleep(time.Second)
			continue
		}
		if len(res) < 2 {
			continue
		}
		var job Job
		if err := json.Unmarshal([]byte(res[1]), &job); err != nil {
			log.Println("bad job", err)
			continue
		}
		if err := w.handle(ctx, job); err != nil {
			log.Println("ingest failed", job.DocumentID, err)
			_, _ = w.cockpit.Exec(ctx, `UPDATE ingest_jobs SET status='failed', error=$2, updated_at=now() WHERE id=$1`, job.JobID, err.Error())
			_, _ = w.cockpit.Exec(ctx, `UPDATE documents SET status='failed' WHERE id=$1`, job.DocumentID)
		}
	}
}

func (w *Worker) handle(ctx context.Context, job Job) error {
	_, _ = w.cockpit.Exec(ctx, `UPDATE ingest_jobs SET status='running', updated_at=now() WHERE id=$1`, job.JobID)
	var key, filename, mime string
	var studioID, userID uuid.UUID
	err := w.cockpit.QueryRow(ctx,
		`SELECT object_key, filename, mime, studio_id, user_id FROM documents WHERE id=$1`,
		job.DocumentID,
	).Scan(&key, &filename, &mime, &studioID, &userID)
	if err != nil {
		return err
	}
	obj, err := w.minio.GetObject(ctx, w.cfg.MinioBucket, key, minio.GetObjectOptions{})
	if err != nil {
		return err
	}
	defer obj.Close()
	data, err := io.ReadAll(obj)
	if err != nil {
		return err
	}
	text, err := extract.Extract(filename, mime, data, w.hirara)
	if err != nil {
		return err
	}
	pieces := extract.Chunk(text, w.cfg.ChunkSize, w.cfg.ChunkOverlap)
	ids := make([]uuid.UUID, len(pieces))
	for i := range pieces {
		ids[i] = uuid.New()
	}
	placeholders := hashEmbed(pieces, w.cfg.EmbedDim)
	if err := w.insertChunks(ctx, ids, job.DocumentID, studioID, userID, pieces, placeholders); err != nil {
		return err
	}
	_, err = w.cockpit.Exec(ctx, `UPDATE ingest_jobs SET status='done', chunks_written=$2, updated_at=now() WHERE id=$1`, job.JobID, len(pieces))
	if err != nil {
		return err
	}
	_, err = w.cockpit.Exec(ctx, `UPDATE documents SET status='ready' WHERE id=$1`, job.DocumentID)
	if err != nil {
		return err
	}
	log.Printf("ingest ready %s chunks=%d", filename, len(pieces))
	if len(pieces) == 0 {
		return nil
	}
	vecs, err := w.embed.Embed(pieces)
	if err != nil {
		log.Println("background embed", err)
		return nil
	}
	for i := range ids {
		if i >= len(vecs) {
			break
		}
		_, err := w.vector.Exec(ctx, `UPDATE chunks SET embedding = $2::vector WHERE id=$1`, ids[i], vecLiteral(vecs[i]))
		if err != nil {
			log.Println("update embedding", err)
			break
		}
	}
	return nil
}

func (w *Worker) insertChunks(ctx context.Context, ids []uuid.UUID, doc, studio, user uuid.UUID, pieces []string, vecs [][]float64) error {
	tx, err := w.vector.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	for i := range pieces {
		_, err := tx.Exec(ctx, `
			INSERT INTO chunks (id, document_id, studio_id, user_id, ordinal, content, embedding, tsv)
			VALUES ($1,$2,$3,$4,$5,$6,$7::vector, to_tsvector('english', $6))`,
			ids[i], doc, studio, user, i, pieces[i], vecLiteral(vecs[i]),
		)
		if err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

func vecLiteral(v []float64) string {
	parts := make([]string, len(v))
	for i, x := range v {
		parts[i] = fmt.Sprintf("%g", x)
	}
	return "[" + strings.Join(parts, ",") + "]"
}

func hashEmbed(texts []string, dim int) [][]float64 {
	out := make([][]float64, len(texts))
	for i, t := range texts {
		vec := make([]float64, dim)
		for _, tok := range strings.Fields(strings.ToLower(t)) {
			h := fnv64(tok)
			vec[int(h%uint64(dim))] += 1
		}
		var n float64
		for _, x := range vec {
			n += x * x
		}
		if n == 0 {
			n = 1
		}
		inv := 1 / sqrt(n)
		for j := range vec {
			vec[j] *= inv
		}
		out[i] = vec
	}
	return out
}

func fnv64(s string) uint64 {
	var h uint64 = 14695981039346656037
	for i := 0; i < len(s); i++ {
		h ^= uint64(s[i])
		h *= 1099511628211
	}
	return h
}

func sqrt(x float64) float64 {
	z := x
	if z == 0 {
		return 0
	}
	for i := 0; i < 12; i++ {
		z = z - (z*z-x)/(2*z)
	}
	return z
}
