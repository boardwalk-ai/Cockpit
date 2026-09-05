package api

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/boardwalk-ai/Cockpit/Backend/guided_generation/go_api/internal/pythonclient"
)

func TestGenerateProxiesEventStream(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/agents/lucas/generate" {
			t.Fatalf("unexpected upstream path: %s", r.URL.Path)
		}
		if r.Header.Get("Accept") != "text/event-stream" {
			t.Fatalf("unexpected Accept header: %s", r.Header.Get("Accept"))
		}
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = io.WriteString(w, "event: delta\ndata: {\"text\":\"hello\"}\n\n")
		if flusher, ok := w.(http.Flusher); ok {
			flusher.Flush()
		}
		_, _ = io.WriteString(w, "event: done\ndata: {}\n\n")
	}))
	defer upstream.Close()

	server := NewServer(pythonclient.New(upstream.URL))
	request := httptest.NewRequest(http.MethodPost, "/api/guided-generation/generate", strings.NewReader(`{"outlines":[{}],"sources":[{}]}`))
	recorder := httptest.NewRecorder()
	server.Handler().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("unexpected status: %d", recorder.Code)
	}
	if got := recorder.Header().Get("Content-Type"); got != "text/event-stream" {
		t.Fatalf("unexpected content type: %s", got)
	}
	if !strings.Contains(recorder.Body.String(), "event: delta") || !strings.Contains(recorder.Body.String(), "event: done") {
		t.Fatalf("unexpected stream body: %s", recorder.Body.String())
	}
}

func TestSupportRoutesProxyToPython(t *testing.T) {
	tests := []struct {
		publicPath string
		pythonPath string
	}{
		{"/api/alvin/search", "/agents/alvin/search"},
		{"/api/zuly/compact", "/agents/zuly/compact"},
		{"/api/spoonie/citation", "/agents/spoonie/citation"},
		{"/api/su/assist", "/agents/su/assist"},
		{"/api/octo/assist", "/agents/octo/assist"},
		{"/api/humanize/stealthgpt", "/humanizer/stealthgpt"},
		{"/api/humanize/undetectable", "/humanizer/undetectable"},
		{"/api/humanize/undetectable/document", "/humanizer/undetectable/document"},
	}

	for _, test := range tests {
		t.Run(test.publicPath, func(t *testing.T) {
			upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != test.pythonPath {
					t.Fatalf("unexpected upstream path: %s", r.URL.Path)
				}
				w.Header().Set("Content-Type", "application/json")
				_, _ = io.WriteString(w, `{"ok":true}`)
			}))
			defer upstream.Close()

			server := NewServer(pythonclient.New(upstream.URL))
			request := httptest.NewRequest(http.MethodPost, test.publicPath, strings.NewReader(`{"test":true}`))
			recorder := httptest.NewRecorder()
			server.Handler().ServeHTTP(recorder, request)

			if recorder.Code != http.StatusOK {
				t.Fatalf("unexpected status: %d", recorder.Code)
			}
			if !strings.Contains(recorder.Body.String(), `"ok":true`) {
				t.Fatalf("unexpected body: %s", recorder.Body.String())
			}
		})
	}
}
