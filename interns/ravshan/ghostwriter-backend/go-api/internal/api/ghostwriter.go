package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"ghostwriter-backend/go-api/internal/models"

	"github.com/google/uuid"
)

func (s *Server) startRun(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Draft map[string]any `json:"draft"`
	}

	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "Invalid JSON body",
		})
		return
	}

	if body.Draft == nil {
		body.Draft = map[string]any{}
	}

	run := &models.Run{
		ID:        uuid.NewString(),
		Draft:     body.Draft,
		Status:    models.RunPending,
		CreatedAt: time.Now(),
		Events:    make(chan models.AgentEvent, 256),
		Messages:  make(chan string, 64),
		Answers:   make(chan models.Answer, 64),
	}

	s.Runs.Create(run)

	go s.startPythonAgent(run)

	writeJSON(w, http.StatusOK, map[string]any{
		"runId": run.ID,
		"mode":  "agentic",
	})
}

func (s *Server) streamRun(w http.ResponseWriter, r *http.Request) {
	runID := r.URL.Query().Get("runId")

	if runID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "runId is required",
		})
		return
	}

	run, ok := s.Runs.Get(runID)
	if !ok {
		writeJSON(w, http.StatusNotFound, map[string]string{
			"error": "Run not found",
		})
		return
	}

	flusher, ok := w.(http.Flusher)
	if !ok {
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "Streaming unsupported",
		})
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache, no-transform")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")

	keepAlive := time.NewTicker(15 * time.Second)
	defer keepAlive.Stop()

	for {
		select {
		case <-r.Context().Done():
			return

		case event := <-run.Events:
			data, err := json.Marshal(event)
			if err != nil {
				continue
			}

			fmt.Fprintf(w, "data: %s\n\n", data)
			flusher.Flush()

			if event.Type == "done" || event.Type == "fatal" {
				return
			}

		case <-keepAlive.C:
			fmt.Fprintf(
				w,
				": keep-alive %d\n\n",
				time.Now().UnixMilli(),
			)
			flusher.Flush()
		}
	}
}

func (s *Server) answerRun(w http.ResponseWriter, r *http.Request) {
	var body struct {
		RunID string `json:"runId"`
		Field string `json:"field"`
		Value any    `json:"value"`
	}

	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "Invalid JSON body",
		})
		return
	}

	if body.RunID == "" || body.Field == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "runId and field are required",
		})
		return
	}

	run, ok := s.Runs.Get(body.RunID)
	if !ok {
		writeJSON(w, http.StatusNotFound, map[string]string{
			"error": "Run not found",
		})
		return
	}

	run.Mu.RLock()
	pendingField := run.PendingField
	run.Mu.RUnlock()

	if pendingField != body.Field {
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": fmt.Sprintf(
				`No pending question for field "%s"`,
				body.Field,
			),
		})
		return
	}

	if err := postPython(
		body.RunID,
		"answer",
		map[string]any{
			"field": body.Field,
			"value": body.Value,
		},
	); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{
			"error": err.Error(),
		})
		return
	}

	run.Mu.Lock()
	run.PendingField = ""
	run.Mu.Unlock()

	writeJSON(w, http.StatusOK, map[string]bool{
		"ok": true,
	})
}

func (s *Server) cancelRun(w http.ResponseWriter, r *http.Request) {
	var body struct {
		RunID string `json:"runId"`
	}

	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "Invalid JSON body",
		})
		return
	}

	if body.RunID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "runId is required",
		})
		return
	}

	run, ok := s.Runs.Get(body.RunID)
	if !ok {
		writeJSON(w, http.StatusNotFound, map[string]string{
			"error": "Run not found",
		})
		return
	}

	run.Mu.Lock()

	if run.Finished {
		run.Mu.Unlock()

		writeJSON(w, http.StatusConflict, map[string]string{
			"error": "Run already finished",
		})
		return
	}

	run.Status = models.RunCancelled
	run.Finished = true
	run.PendingField = ""

	run.Mu.Unlock()

	_ = postPython(
		body.RunID,
		"cancel",
		nil,
	)

	select {
	case run.Events <- models.AgentEvent{
		Type:  "fatal",
		Error: "Run cancelled by user.",
	}:
	default:
	}

	writeJSON(w, http.StatusOK, map[string]bool{
		"ok": true,
	})
}

func (s *Server) pauseRun(w http.ResponseWriter, r *http.Request) {
	var body struct {
		RunID string `json:"runId"`
	}

	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "Invalid JSON body",
		})
		return
	}

	if body.RunID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "runId is required",
		})
		return
	}

	run, ok := s.Runs.Get(body.RunID)
	if !ok {
		writeJSON(w, http.StatusNotFound, map[string]string{
			"error": "Run not found",
		})
		return
	}

	run.Mu.Lock()

	if run.Finished {
		run.Mu.Unlock()

		writeJSON(w, http.StatusConflict, map[string]string{
			"error": "Run already finished",
		})
		return
	}

	run.PauseRequested = true

	run.Mu.Unlock()

	if err := postPython(
		body.RunID,
		"pause",
		nil,
	); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{
			"error": err.Error(),
		})
		return
	}

	writeJSON(w, http.StatusOK, map[string]bool{
		"ok": true,
	})
}

func (s *Server) messageRun(w http.ResponseWriter, r *http.Request) {
	runID := r.PathValue("runId")

	run, ok := s.Runs.Get(runID)
	if !ok {
		writeJSON(w, http.StatusNotFound, map[string]string{
			"error": "Run not found.",
		})
		return
	}

	run.Mu.RLock()
	finished := run.Finished
	run.Mu.RUnlock()

	if finished {
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": "Run has already finished.",
		})
		return
	}

	var body struct {
		Text string `json:"text"`
	}

	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "text is required.",
		})
		return
	}

	body.Text = strings.TrimSpace(body.Text)

	if body.Text == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "text is required.",
		})
		return
	}

	run.Events <- models.AgentEvent{
		Type: "user_message",
		Text: body.Text,
	}

	if err := postPython(
		runID,
		"message",
		map[string]any{
			"text": body.Text,
		},
	); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{
			"error": err.Error(),
		})
		return
	}

	writeJSON(w, http.StatusOK, map[string]bool{
		"ok": true,
	})
}
