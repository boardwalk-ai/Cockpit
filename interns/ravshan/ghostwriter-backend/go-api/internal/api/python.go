package api

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"ghostwriter-backend/go-api/internal/models"
)

func pythonBaseURL() string {
	if value := os.Getenv("PYTHON_AGENT_URL"); value != "" {
		return value
	}
	return "http://127.0.0.1:8090"
}

func (s *Server) startPythonAgent(run *models.Run) {
	body, _ := json.Marshal(map[string]any{
		"draft": run.Draft,
	})

	resp, err := http.Post(
		fmt.Sprintf(
			"%s/runs/%s/start",
			pythonBaseURL(),
			run.ID,
		),
		"application/json",
		bytes.NewReader(body),
	)

	if err != nil {
		run.Events <- models.AgentEvent{
			Type:  "fatal",
			Error: err.Error(),
		}
		return
	}

	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		data, _ := io.ReadAll(resp.Body)

		run.Events <- models.AgentEvent{
			Type:  "fatal",
			Error: string(data),
		}
		return
	}

	go s.streamPythonEvents(run)
}

func (s *Server) streamPythonEvents(run *models.Run) {
	client := &http.Client{
		Timeout: 0,
	}

	req, _ := http.NewRequest(
		http.MethodGet,
		fmt.Sprintf(
			"%s/runs/%s/events",
			pythonBaseURL(),
			run.ID,
		),
		nil,
	)

	resp, err := client.Do(req)
	if err != nil {
		run.Events <- models.AgentEvent{
			Type:  "fatal",
			Error: err.Error(),
		}
		return
	}

	defer resp.Body.Close()

	scanner := bufio.NewScanner(resp.Body)

	for scanner.Scan() {
		line := scanner.Text()

		if !strings.HasPrefix(line, "data: ") {
			continue
		}

		raw := strings.TrimPrefix(line, "data: ")

		var event models.AgentEvent

		if err := json.Unmarshal(
			[]byte(raw),
			&event,
		); err != nil {
			continue
		}

		if event.Type == "question" {
			run.Mu.Lock()
			run.PendingField = event.Field
			run.Status = models.RunWaitingForUser
			run.Mu.Unlock()
		}

		if event.Type == "done" {
			run.Mu.Lock()
			run.Finished = true
			run.Status = models.RunFinished
			run.Mu.Unlock()
		}

		if event.Type == "fatal" {
			run.Mu.Lock()
			run.Finished = true
			if run.Status != models.RunCancelled {
				run.Status = models.RunError
			}
			run.Mu.Unlock()
		}

		run.Events <- event
	}
}

func postPython(
	runID string,
	path string,
	payload any,
) error {
	var body io.Reader

	if payload != nil {
		data, _ := json.Marshal(payload)
		body = bytes.NewReader(data)
	}

	client := &http.Client{
		Timeout: 10 * time.Second,
	}

	req, err := http.NewRequest(
		http.MethodPost,
		fmt.Sprintf(
			"%s/runs/%s/%s",
			pythonBaseURL(),
			runID,
			path,
		),
		body,
	)

	if err != nil {
		return err
	}

	req.Header.Set(
		"Content-Type",
		"application/json",
	)

	resp, err := client.Do(req)
	if err != nil {
		return err
	}

	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		data, _ := io.ReadAll(resp.Body)
		return fmt.Errorf(
			"python agent: %s",
			string(data),
		)
	}

	return nil
}
