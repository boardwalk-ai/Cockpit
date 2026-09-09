package search

import (
	"context"
	"encoding/json"
	"log"
	"net/http"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/octopilot/cockpit-go/internal/embedclient"
)

type Hit struct {
	ChunkID    uuid.UUID `json:"chunk_id"`
	DocumentID uuid.UUID `json:"document_id"`
	Ordinal    int       `json:"ordinal"`
	Content    string    `json:"content"`
	Score      float64   `json:"score"`
}

type Server struct {
	vector *pgxpool.Pool
	embed  *embedclient.Client
	topK   int
}

func New(vector *pgxpool.Pool, embed *embedclient.Client, topK int) *Server {
	return &Server{vector: vector, embed: embed, topK: topK}
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/health" {
		w.Write([]byte(`{"ok":true}`))
		return
	}
	if r.Method != http.MethodPost || r.URL.Path != "/search" {
		http.NotFound(w, r)
		return
	}
	var req struct {
		UserID    uuid.UUID `json:"user_id"`
		StudioID  uuid.UUID `json:"studio_id"`
		Query     string    `json:"query"`
		TopK      int       `json:"top_k"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	k := req.TopK
	if k <= 0 {
		k = s.topK
	}
	hits, err := s.Search(r.Context(), req.UserID, req.StudioID, req.Query, k)
	if err != nil {
		log.Println("search", err)
		http.Error(w, err.Error(), 500)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"hits": hits})
}

func (s *Server) Search(ctx context.Context, userID, studioID uuid.UUID, query string, topK int) ([]Hit, error) {
	vecs, err := s.embed.Embed([]string{query})
	if err != nil {
		return nil, err
	}
	if len(vecs) == 0 {
		return nil, nil
	}
	qvec := vecLiteral(vecs[0])
	cand := topK * 4
	if cand < 20 {
		cand = 20
	}
	rows, err := s.vector.Query(ctx, `
        WITH dense AS (
            SELECT id, document_id, ordinal, content,
                   ROW_NUMBER() OVER (ORDER BY embedding <=> $1::vector) AS rnk
            FROM chunks
            WHERE user_id = $2 AND studio_id = $3
            ORDER BY embedding <=> $1::vector
            LIMIT $5
        ),
        lexical AS (
            SELECT id, document_id, ordinal, content,
                   ROW_NUMBER() OVER (
                       ORDER BY ts_rank(tsv, plainto_tsquery('english', $4)) DESC
                   ) AS rnk
            FROM chunks
            WHERE user_id = $2 AND studio_id = $3
              AND tsv @@ plainto_tsquery('english', $4)
            LIMIT $5
        ),
        fused AS (
            SELECT id, document_id, ordinal, content,
                   SUM(1.0 / (60 + rnk)) AS score
            FROM (
                SELECT * FROM dense
                UNION ALL
                SELECT * FROM lexical
            ) u
            GROUP BY id, document_id, ordinal, content
        )
        SELECT id, document_id, ordinal, content, score
        FROM fused
        ORDER BY score DESC
        LIMIT $6
	`, qvec, userID, studioID, query, cand, topK)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var hits []Hit
	for rows.Next() {
		var h Hit
		if err := rows.Scan(&h.ChunkID, &h.DocumentID, &h.Ordinal, &h.Content, &h.Score); err != nil {
			return nil, err
		}
		hits = append(hits, h)
	}
	return hits, rows.Err()
}

func vecLiteral(v []float64) string {
	b := make([]byte, 0, 8*len(v)+2)
	b = append(b, '[')
	for i, x := range v {
		if i > 0 {
			b = append(b, ',')
		}
		b = append(b, []byte(trimFloat(x))...)
	}
	b = append(b, ']')
	return string(b)
}

func trimFloat(x float64) string {
	return json.Number(jsonNumber(x)).String()
}

func jsonNumber(x float64) string {
	b, _ := json.Marshal(x)
	return string(b)
}
