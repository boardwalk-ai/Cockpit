package api

import (
	"encoding/json"
	"net/http"

	"ghostwriter-backend/go-api/internal/store"
)

type Server struct {
	Runs      *store.RunStore
	Workspace *store.WorkspaceStore
}

func NewServer() *Server {
	return &Server{
		Runs:      store.NewRunStore(),
		Workspace: store.NewWorkspaceStore("data/ghostwriter.json"),
	}
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set(
			"Access-Control-Allow-Headers",
			"Content-Type, Accept",
		)
		w.Header().Set(
			"Access-Control-Allow-Methods",
			"GET, POST, PATCH, DELETE, OPTIONS",
		)

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", s.health)

	mux.HandleFunc("POST /api/ghostwriter/start", s.startRun)
	mux.HandleFunc("GET /api/ghostwriter/run", s.streamRun)
	mux.HandleFunc("POST /api/ghostwriter/answer", s.answerRun)
	mux.HandleFunc("POST /api/ghostwriter/cancel", s.cancelRun)
	mux.HandleFunc("POST /api/ghostwriter/pause", s.pauseRun)
	mux.HandleFunc(
		"POST /api/ghostwriter/runs/{runId}/message",
		s.messageRun,
	)

	mux.HandleFunc(
		"GET /api/ghostwriter/workspace",
		s.workspaceState,
	)
	mux.HandleFunc(
		"POST /api/ghostwriter/folders",
		s.createFolder,
	)
	mux.HandleFunc(
		"POST /api/ghostwriter/threads",
		s.saveThread,
	)
	mux.HandleFunc(
		"GET /api/ghostwriter/credits",
		s.credits,
	)
	mux.HandleFunc(
		"GET /api/ghostwriter/session",
		s.session,
	)

	return cors(mux)
}

func (s *Server) health(
	w http.ResponseWriter,
	r *http.Request,
) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status":  "ok",
		"service": "ghostwriter-go-api",
	})
}
