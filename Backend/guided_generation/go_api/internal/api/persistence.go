package api

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/boardwalk-ai/Cockpit/Backend/guided_generation/go_api/internal/store"
)

const maxJSONBody = 4 << 20

func (s *Server) listThreads(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.store.ListThreads(requestUID(r)))
}

func (s *Server) createThread(w http.ResponseWriter, r *http.Request) {
	var input store.CreateThread
	if err := decodeJSON(w, r, &input); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	if strings.TrimSpace(input.RunID) == "" || strings.TrimSpace(input.Prompt) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "runId and prompt are required"})
		return
	}
	thread, err := s.store.CreateThread(requestUID(r), input)
	if errors.Is(err, store.ErrFolderNotFound) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "folder not found"})
		return
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to persist thread"})
		return
	}
	writeJSON(w, http.StatusCreated, thread)
}

func (s *Server) getThread(w http.ResponseWriter, r *http.Request) {
	thread, err := s.store.GetThread(requestUID(r), r.PathValue("threadID"))
	if errors.Is(err, store.ErrNotFound) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "thread not found"})
		return
	}
	writeJSON(w, http.StatusOK, thread)
}

func (s *Server) updateThread(w http.ResponseWriter, r *http.Request) {
	fields := map[string]json.RawMessage{}
	if err := decodeJSON(w, r, &fields); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	patch, err := parseThreadPatch(fields)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	thread, err := s.store.UpdateThread(requestUID(r), r.PathValue("threadID"), patch)
	if errors.Is(err, store.ErrNotFound) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "thread not found"})
		return
	}
	if errors.Is(err, store.ErrFolderNotFound) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "folder not found"})
		return
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to persist thread"})
		return
	}
	writeJSON(w, http.StatusOK, thread)
}

func (s *Server) deleteThread(w http.ResponseWriter, r *http.Request) {
	err := s.store.DeleteThread(requestUID(r), r.PathValue("threadID"))
	if errors.Is(err, store.ErrNotFound) {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to delete thread"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) listFolders(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.store.ListFolders(requestUID(r)))
}

func (s *Server) createFolder(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Name  string `json:"name"`
		Color string `json:"color"`
		Order int64  `json:"order"`
	}
	if err := decodeJSON(w, r, &input); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	input.Name = strings.TrimSpace(input.Name)
	if input.Name == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "name is required"})
		return
	}
	if input.Color == "" {
		input.Color = "#8b5cf6"
	}
	folder, err := s.store.CreateFolder(requestUID(r), input.Name, input.Color, input.Order)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to persist folder"})
		return
	}
	writeJSON(w, http.StatusCreated, folder)
}

func (s *Server) updateFolder(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Name  *string `json:"name"`
		Color *string `json:"color"`
		Order *int64  `json:"order"`
	}
	if err := decodeJSON(w, r, &input); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	if input.Name != nil {
		clean := strings.TrimSpace(*input.Name)
		if clean == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "name cannot be empty"})
			return
		}
		input.Name = &clean
	}
	folder, err := s.store.UpdateFolder(
		requestUID(r), r.PathValue("folderID"), input.Name, input.Color, input.Order,
	)
	if errors.Is(err, store.ErrNotFound) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "folder not found"})
		return
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to persist folder"})
		return
	}
	writeJSON(w, http.StatusOK, folder)
}

func (s *Server) deleteFolder(w http.ResponseWriter, r *http.Request) {
	err := s.store.DeleteFolder(requestUID(r), r.PathValue("folderID"))
	if errors.Is(err, store.ErrNotFound) {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to delete folder"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) getCredits(w http.ResponseWriter, r *http.Request) {
	balance, err := s.store.Balance(requestUID(r))
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to load credits"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]int{
		"octo_credits":      balance,
		"word_credits":      balance,
		"humanizer_credits": balance,
		"source_credits":    balance,
	})
}

func (s *Server) deductCredits(w http.ResponseWriter, r *http.Request) {
	var input struct {
		CreditType     string `json:"credit_type"`
		Amount         int    `json:"amount"`
		IdempotencyKey string `json:"idempotency_key"`
	}
	if err := decodeJSON(w, r, &input); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	if input.Amount <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "amount must be greater than zero"})
		return
	}
	switch input.CreditType {
	case "word", "source", "humanizer", "octo", "":
	default:
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unsupported credit_type"})
		return
	}
	result, err := s.store.Deduct(requestUID(r), input.Amount, input.IdempotencyKey)
	if errors.Is(err, store.ErrInsufficientCredits) {
		writeJSON(w, http.StatusPaymentRequired, map[string]string{"error": "insufficient credits"})
		return
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to deduct credits"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]int{
		"charge":            result.Charge,
		"octo_credits":      result.OctoCredits,
		"word_credits":      result.OctoCredits,
		"humanizer_credits": result.OctoCredits,
		"source_credits":    result.OctoCredits,
	})
}

func requestUID(r *http.Request) string {
	if uid := strings.TrimSpace(r.Header.Get("X-User-ID")); uid != "" {
		return uid
	}
	if authorization := strings.TrimSpace(r.Header.Get("Authorization")); authorization != "" {
		hash := sha256.Sum256([]byte(authorization))
		return "token-" + hex.EncodeToString(hash[:12])
	}
	return "dev-user"
}

func decodeJSON(w http.ResponseWriter, r *http.Request, target any) error {
	r.Body = http.MaxBytesReader(w, r.Body, maxJSONBody)
	decoder := json.NewDecoder(r.Body)
	if err := decoder.Decode(target); err != nil {
		if errors.Is(err, io.EOF) {
			return errors.New("request body is required")
		}
		return errors.New("invalid JSON body")
	}
	return nil
}

func parseThreadPatch(fields map[string]json.RawMessage) (store.UpdateThread, error) {
	patch := store.UpdateThread{}
	if raw, ok := fields["title"]; ok {
		if err := json.Unmarshal(raw, &patch.Title); err != nil {
			return patch, errors.New("title must be a string")
		}
	}
	if raw, ok := fields["status"]; ok {
		if err := json.Unmarshal(raw, &patch.Status); err != nil {
			return patch, errors.New("status must be a string")
		}
		if patch.Status != nil && *patch.Status != "running" && *patch.Status != "finished" && *patch.Status != "error" {
			return patch, errors.New("status must be running, finished, or error")
		}
	}
	if raw, ok := fields["folderId"]; ok {
		patch.FolderSet = true
		var value *string
		if err := json.Unmarshal(raw, &value); err != nil {
			return patch, errors.New("folderId must be a string or null")
		}
		if value != nil && *value != "__unfiled__" {
			patch.FolderID = value
		}
	}
	if raw, ok := fields["essay"]; ok {
		patch.EssaySet = true
		if string(raw) != "null" {
			if err := json.Unmarshal(raw, &patch.Essay); err != nil {
				return patch, errors.New("essay must be a string or null")
			}
		}
	}
	if raw, ok := fields["messages"]; ok {
		messages := []store.Message{}
		if err := json.Unmarshal(raw, &messages); err != nil {
			return patch, errors.New("messages must be an array")
		}
		patch.Messages = &messages
	}
	if raw, ok := fields["wordCount"]; ok {
		patch.WordCountSet = true
		if string(raw) != "null" {
			if err := json.Unmarshal(raw, &patch.WordCount); err != nil {
				return patch, errors.New("wordCount must be a number or null")
			}
		}
	}
	if raw, ok := fields["citationStyle"]; ok {
		patch.CitationSet = true
		if string(raw) != "null" {
			if err := json.Unmarshal(raw, &patch.CitationStyle); err != nil {
				return patch, errors.New("citationStyle must be a string or null")
			}
		}
	}
	if raw, ok := fields["runState"]; ok {
		patch.RunStateSet = true
		patch.RunState = append(json.RawMessage(nil), raw...)
	}
	return patch, nil
}
