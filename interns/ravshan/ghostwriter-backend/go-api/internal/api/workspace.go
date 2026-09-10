package api

import (
	"encoding/json"
	"net/http"
	"strings"

	"ghostwriter-backend/go-api/internal/store"
)

func (s *Server) workspaceState(
	w http.ResponseWriter,
	r *http.Request,
) {
	state := s.Workspace.Snapshot()

	writeJSON(w, http.StatusOK, state)
}

func (s *Server) createFolder(
	w http.ResponseWriter,
	r *http.Request,
) {
	var body struct {
		Name string `json:"name"`
	}

	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "Invalid JSON body",
		})
		return
	}

	body.Name = strings.TrimSpace(body.Name)

	if body.Name == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "name is required",
		})
		return
	}

	folder := s.Workspace.CreateFolder(body.Name)

	writeJSON(w, http.StatusCreated, folder)
}

func (s *Server) saveThread(
	w http.ResponseWriter,
	r *http.Request,
) {
	var thread store.Thread

	if err := json.NewDecoder(r.Body).Decode(&thread); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "Invalid JSON body",
		})
		return
	}

	thread.Title = strings.TrimSpace(thread.Title)

	if thread.Title == "" {
		thread.Title = "Untitled GhostWriter Essay"
	}

	if thread.Status == "" {
		thread.Status = "Finished"
	}

	saved := s.Workspace.SaveThread(thread)

	writeJSON(w, http.StatusOK, saved)
}

func (s *Server) credits(
	w http.ResponseWriter,
	r *http.Request,
) {
	state := s.Workspace.Snapshot()

	writeJSON(w, http.StatusOK, map[string]any{
		"credits": state.Credits,
	})
}

func (s *Server) session(
	w http.ResponseWriter,
	r *http.Request,
) {
	state := s.Workspace.Snapshot()

	writeJSON(w, http.StatusOK, map[string]any{
		"name": state.SessionName,
	})
}
