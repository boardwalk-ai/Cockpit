package config

import (
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Listen        string
	Upstream      string
	Role          string
	RedisURL      string
	CockpitDB     string
	VectorDB      string
	SharedDB      string
	MinioEndpoint string
	MinioAccess   string
	MinioSecret   string
	MinioBucket   string
	MinioSecure   bool
	EmbedURL      string
	HiraraURL     string
	HiraraToken   string
	FirebaseProj   string
	CorsOrigins    string
	AllowDevHeader bool
	ChunkSize     int
	ChunkOverlap  int
	EmbedDim      int
	TopK          int
}

func getenv(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

func getenvInt(k string, d int) int {
	if v := os.Getenv(k); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return d
}

func pgURL(s string) string {
	s = strings.ReplaceAll(s, "postgresql+asyncpg://", "postgres://")
	s = strings.ReplaceAll(s, "postgresql+psycopg://", "postgres://")
	return s
}

func Load() Config {
	return Config{
		Listen:         getenv("GO_LISTEN", "127.0.0.1:8100"),
		Upstream:       getenv("UPSTREAM_API", "http://127.0.0.1:8101"),
		Role:           getenv("GO_ROLE", "gateway"),
		RedisURL:       getenv("REDIS_URL", "redis://127.0.0.1:6379/0"),
		CockpitDB:      pgURL(getenv("GO_COCKPIT_DATABASE_URL", getenv("COCKPIT_DATABASE_URL", "postgres://cockpit:cockpit@127.0.0.1:5433/cockpit"))),
		VectorDB:       pgURL(getenv("GO_VECTOR_DATABASE_URL", getenv("VECTOR_DATABASE_URL", "postgres://vector:vector@127.0.0.1:5434/vector"))),
		SharedDB:       pgURL(getenv("GO_SHARED_DATABASE_URL", getenv("SHARED_DATABASE_URL", ""))),
		MinioEndpoint:  strings.TrimPrefix(strings.TrimPrefix(getenv("OBJECT_STORE_ENDPOINT", "http://127.0.0.1:9000"), "http://"), "https://"),
		MinioAccess:    getenv("OBJECT_STORE_ACCESS_KEY", "minioadmin"),
		MinioSecret:    getenv("OBJECT_STORE_SECRET_KEY", "minioadmin"),
		MinioBucket:    getenv("OBJECT_STORE_BUCKET", "cockpit-rag"),
		MinioSecure:    false,
		EmbedURL:       getenv("EMBED_SERVICE_URL", "http://127.0.0.1:8091"),
		HiraraURL:      getenv("HIRARA_HUB_URL", "http://127.0.0.1:8080"),
		HiraraToken:    getenv("HIRARA_HUB_TOKEN", ""),
		FirebaseProj:   getenv("FIREBASE_PROJECT_ID", ""),
		CorsOrigins:    getenv("CORS_ORIGINS", "https://studystudio.octopilothub.com"),
		AllowDevHeader: getenv("ALLOW_DEV_USER_HEADER", "true") != "false",
		ChunkSize:      getenvInt("RAG_CHUNK_TOKENS", 512),
		ChunkOverlap:   getenvInt("RAG_CHUNK_OVERLAP", 64),
		EmbedDim:       getenvInt("EMBEDDING_DIM", 1024),
		TopK:           getenvInt("RAG_TOP_K", 8),
	}
}
