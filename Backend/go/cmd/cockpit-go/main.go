package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/octopilot/cockpit-go/internal/auth"
	"github.com/octopilot/cockpit-go/internal/config"
	"github.com/octopilot/cockpit-go/internal/embedclient"
	"github.com/octopilot/cockpit-go/internal/gateway"
	"github.com/octopilot/cockpit-go/internal/ingest"
	"github.com/octopilot/cockpit-go/internal/search"
	"github.com/redis/go-redis/v9"
)

func main() {
	cfg := config.Load()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	rdb := mustRedis(cfg.RedisURL)

	switch cfg.Role {
	case "gateway":
		cockpit := mustPool(ctx, cfg.CockpitDB)
		defer cockpit.Close()
		var shared *pgxpool.Pool
		if cfg.SharedDB != "" {
			shared = mustPool(ctx, cfg.SharedDB)
			defer shared.Close()
		}
		v := auth.New(cfg.FirebaseProj, cfg.AllowDevHeader, shared)
		srv, err := gateway.New(cfg, cockpit, rdb, v)
		if err != nil {
			log.Fatal(err)
		}
		runHTTP(ctx, cfg.Listen, srv)
	case "search", "worker":
		vector := mustPool(ctx, cfg.VectorDB)
		defer vector.Close()
		cockpit := mustPool(ctx, cfg.CockpitDB)
		defer cockpit.Close()
		embed := embedclient.New(cfg.EmbedURL)
		mux := http.NewServeMux()
		mux.Handle("/", search.New(vector, embed, cfg.TopK))
		go func() {
			w, err := ingest.New(cfg, cockpit, vector, rdb)
			if err != nil {
				log.Fatal(err)
			}
			if err := w.Run(ctx); err != nil && ctx.Err() == nil {
				log.Fatal(err)
			}
		}()
		listen := cfg.Listen
		if listen == "127.0.0.1:8100" {
			listen = "127.0.0.1:8092"
		}
		runHTTP(ctx, listen, mux)
	default:
		log.Fatal("unknown GO_ROLE ", cfg.Role)
	}
}

func mustRedis(url string) *redis.Client {
	opt, err := redis.ParseURL(url)
	if err != nil {
		log.Fatal(err)
	}
	return redis.NewClient(opt)
}

func mustPool(ctx context.Context, url string) *pgxpool.Pool {
	p, err := pgxpool.New(ctx, url)
	if err != nil {
		log.Fatal(err)
	}
	if err := p.Ping(ctx); err != nil {
		log.Fatal(err)
	}
	return p
}

func runHTTP(ctx context.Context, addr string, h http.Handler) {
	srv := &http.Server{Addr: addr, Handler: h, ReadHeaderTimeout: 10 * time.Second}
	go func() {
		<-ctx.Done()
		c, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(c)
	}()
	log.Println("listening", addr)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}
