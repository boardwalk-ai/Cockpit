package api

import (
	"encoding/json"
	"net/http"

	"ghostwriter-backend/go-api/internal/store"
)

type Server struct {
	Runs *store.RunStore
}

func NewServer() *Server {
	return &Server{
		Runs: store.NewRunStore(),
	}
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", s.health)
	mux.HandleFunc("POST /api/ghostwriter/start", s.startRun)
	mux.HandleFunc("GET /api/ghostwriter/run", s.streamRun)
	mux.HandleFunc("POST /api/ghostwriter/answer", s.answerRun)
	mux.HandleFunc("POST /api/ghostwriter/cancel", s.cancelRun)
	mux.HandleFunc("POST /api/ghostwriter/pause", s.pauseRun)
	mux.HandleFunc("POST /api/ghostwriter/runs/{runId}/message", s.messageRun)

	return mux
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status":  "ok",
		"service": "ghostwriter-go-api",
	})
}
