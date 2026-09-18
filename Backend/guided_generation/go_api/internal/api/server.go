package api

import (
	"encoding/json"
	"io"
	"net/http"

	"github.com/boardwalk-ai/Cockpit/Backend/guided_generation/go_api/internal/pythonclient"
	"github.com/boardwalk-ai/Cockpit/Backend/guided_generation/go_api/internal/store"
)

type Server struct {
	python *pythonclient.Client
	store  *store.Store
}

func NewServer(python *pythonclient.Client, stores ...*store.Store) *Server {
	dataStore := (*store.Store)(nil)
	if len(stores) > 0 {
		dataStore = stores[0]
	}
	if dataStore == nil {
		dataStore, _ = store.New("", 1000)
	}
	return &Server{python: python, store: dataStore}
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", s.health)
	mux.HandleFunc("POST /api/guided-generation/analyze", s.analyze)
	mux.HandleFunc("POST /api/guided-generation/outlines", s.outlines)
	mux.HandleFunc("POST /api/guided-generation/generate", s.generate)

	mux.HandleFunc("POST /api/alvin/search", s.alvin)
	mux.HandleFunc("POST /api/zuly/compact", s.zuly)
	mux.HandleFunc("POST /api/spoonie/citation", s.spoonie)
	mux.HandleFunc("POST /api/su/assist", s.su)
	mux.HandleFunc("POST /api/octo/assist", s.octo)

	mux.HandleFunc("POST /api/humanize/stealthgpt", s.humanizeStealthGPT)
	mux.HandleFunc("POST /api/humanize/undetectable", s.humanizeUndetectable)
	mux.HandleFunc("POST /api/humanize/undetectable/document", s.humanizeUndetectableDocument)

	mux.HandleFunc("GET /api/guided-generation/credits", s.getCredits)
	mux.HandleFunc("POST /api/guided-generation/credits/deduct", s.deductCredits)

	mux.HandleFunc("GET /api/v1/ghostwriter/threads", s.listThreads)
	mux.HandleFunc("POST /api/v1/ghostwriter/threads", s.createThread)
	mux.HandleFunc("GET /api/v1/ghostwriter/threads/{threadID}", s.getThread)
	mux.HandleFunc("PATCH /api/v1/ghostwriter/threads/{threadID}", s.updateThread)
	mux.HandleFunc("DELETE /api/v1/ghostwriter/threads/{threadID}", s.deleteThread)
	mux.HandleFunc("GET /api/v1/ghostwriter/folders", s.listFolders)
	mux.HandleFunc("POST /api/v1/ghostwriter/folders", s.createFolder)
	mux.HandleFunc("PATCH /api/v1/ghostwriter/folders/{folderID}", s.updateFolder)
	mux.HandleFunc("DELETE /api/v1/ghostwriter/folders/{folderID}", s.deleteFolder)
	mux.HandleFunc("GET /api/v1/me/credits", s.getCredits)
	mux.HandleFunc("POST /api/v1/me/credits/deduct", s.deductCredits)

	return mux
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "service": "guided-generation-go-api"})
}

func (s *Server) analyze(w http.ResponseWriter, r *http.Request) {
	s.forward(w, r, "/agents/hein/analyze")
}

func (s *Server) outlines(w http.ResponseWriter, r *http.Request) {
	s.forward(w, r, "/agents/lily/generate")
}

func (s *Server) generate(w http.ResponseWriter, r *http.Request) {
	s.forwardStream(w, r, "/agents/lucas/generate")
}

func (s *Server) alvin(w http.ResponseWriter, r *http.Request) {
	s.forward(w, r, "/agents/alvin/search")
}

func (s *Server) zuly(w http.ResponseWriter, r *http.Request) {
	s.forward(w, r, "/agents/zuly/compact")
}

func (s *Server) spoonie(w http.ResponseWriter, r *http.Request) {
	s.forward(w, r, "/agents/spoonie/citation")
}

func (s *Server) su(w http.ResponseWriter, r *http.Request) {
	s.forward(w, r, "/agents/su/assist")
}

func (s *Server) octo(w http.ResponseWriter, r *http.Request) {
	s.forward(w, r, "/agents/octo/assist")
}

func (s *Server) humanizeStealthGPT(w http.ResponseWriter, r *http.Request) {
	s.forward(w, r, "/humanizer/stealthgpt")
}

func (s *Server) humanizeUndetectable(w http.ResponseWriter, r *http.Request) {
	s.forward(w, r, "/humanizer/undetectable")
}

func (s *Server) humanizeUndetectableDocument(w http.ResponseWriter, r *http.Request) {
	s.forward(w, r, "/humanizer/undetectable/document")
}

func (s *Server) forward(w http.ResponseWriter, r *http.Request, path string) {
	r.Body = http.MaxBytesReader(w, r.Body, maxJSONBody)
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	data, status, err := s.python.Post(r.Context(), path, body)
	if err != nil && status == 0 {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "agent service unavailable"})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(data)
}

func (s *Server) forwardStream(w http.ResponseWriter, r *http.Request, path string) {
	r.Body = http.MaxBytesReader(w, r.Body, maxJSONBody)
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	res, err := s.python.Stream(r.Context(), path, body)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "agent service unavailable"})
		return
	}
	defer res.Body.Close()

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(res.StatusCode)

	flusher, canFlush := w.(http.Flusher)
	buffer := make([]byte, 4096)
	for {
		n, readErr := res.Body.Read(buffer)
		if n > 0 {
			if _, writeErr := w.Write(buffer[:n]); writeErr != nil {
				return
			}
			if canFlush {
				flusher.Flush()
			}
		}
		if readErr != nil {
			return
		}
	}
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
