package api

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/boardwalk-ai/Cockpit/Backend/guided_generation/go_api/internal/pythonclient"
	"github.com/boardwalk-ai/Cockpit/Backend/guided_generation/go_api/internal/store"
)

func TestPersistenceAndCreditRoutes(t *testing.T) {
	upstream := httptest.NewServer(http.NotFoundHandler())
	defer upstream.Close()
	dataStore, err := store.New("", 500)
	if err != nil {
		t.Fatal(err)
	}
	handler := NewServer(pythonclient.New(upstream.URL), dataStore).Handler()

	folderResponse := apiRequest(t, handler, http.MethodPost, "/api/v1/ghostwriter/folders", map[string]any{
		"name": "Research", "color": "#123456", "order": 1,
	})
	if folderResponse.Code != http.StatusCreated {
		t.Fatalf("create folder returned %d: %s", folderResponse.Code, folderResponse.Body.String())
	}
	var folder store.Folder
	decodeResponse(t, folderResponse, &folder)

	threadResponse := apiRequest(t, handler, http.MethodPost, "/api/v1/ghostwriter/threads", map[string]any{
		"runId": "run-1", "prompt": "Write an essay", "folderId": folder.ID,
		"wordCount": 1000, "citationStyle": "APA",
	})
	if threadResponse.Code != http.StatusCreated {
		t.Fatalf("create thread returned %d: %s", threadResponse.Code, threadResponse.Body.String())
	}
	var thread store.ThreadFull
	decodeResponse(t, threadResponse, &thread)

	patchResponse := apiRequest(t, handler, http.MethodPatch, "/api/v1/ghostwriter/threads/"+thread.ID, map[string]any{
		"status": "finished", "essay": "Complete", "runState": map[string]any{"savedAt": "now"},
	})
	if patchResponse.Code != http.StatusOK {
		t.Fatalf("patch thread returned %d: %s", patchResponse.Code, patchResponse.Body.String())
	}

	listResponse := apiRequest(t, handler, http.MethodGet, "/api/v1/ghostwriter/threads", nil)
	var threads []store.Thread
	decodeResponse(t, listResponse, &threads)
	if len(threads) != 1 || threads[0].Status != "finished" {
		t.Fatalf("unexpected thread list: %#v", threads)
	}

	creditResponse := apiRequest(t, handler, http.MethodPost, "/api/v1/me/credits/deduct", map[string]any{
		"credit_type": "word", "amount": 100, "idempotency_key": "run-1:word",
	})
	var credits map[string]int
	decodeResponse(t, creditResponse, &credits)
	if credits["octo_credits"] != 400 {
		t.Fatalf("unexpected balance: %#v", credits)
	}
	retryResponse := apiRequest(t, handler, http.MethodPost, "/api/v1/me/credits/deduct", map[string]any{
		"credit_type": "word", "amount": 100, "idempotency_key": "run-1:word",
	})
	decodeResponse(t, retryResponse, &credits)
	if credits["octo_credits"] != 400 {
		t.Fatalf("idempotency failed: %#v", credits)
	}

	otherUser := httptest.NewRequest(http.MethodGet, "/api/v1/ghostwriter/threads", nil)
	otherUser.Header.Set("X-User-ID", "user-2")
	otherRecorder := httptest.NewRecorder()
	handler.ServeHTTP(otherRecorder, otherUser)
	var otherThreads []store.Thread
	decodeResponse(t, otherRecorder, &otherThreads)
	if len(otherThreads) != 0 {
		t.Fatalf("user isolation failed: %#v", otherThreads)
	}
}

func apiRequest(t *testing.T, handler http.Handler, method, path string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var reader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		reader = bytes.NewReader(encoded)
	}
	request := httptest.NewRequest(method, path, reader)
	request.Header.Set("X-User-ID", "user-1")
	request.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)
	return recorder
}

func decodeResponse(t *testing.T, recorder *httptest.ResponseRecorder, target any) {
	t.Helper()
	if err := json.Unmarshal(recorder.Body.Bytes(), target); err != nil {
		t.Fatalf("invalid JSON response %q: %v", recorder.Body.String(), err)
	}
}
