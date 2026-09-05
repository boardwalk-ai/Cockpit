package pythonclient

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"time"
)

type Client struct {
	baseURL   string
	http      *http.Client
	streaming *http.Client
}

func New(baseURL string) *Client {
	return &Client{
		baseURL: baseURL,
		http: &http.Client{
			Timeout: 45 * time.Second,
		},
		streaming: &http.Client{},
	}
}

func (c *Client) Post(ctx context.Context, path string, body []byte) ([]byte, int, error) {
	req, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		c.baseURL+path,
		bytes.NewReader(body),
	)
	if err != nil {
		return nil, 0, err
	}

	req.Header.Set("Content-Type", "application/json")

	res, err := c.http.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer res.Body.Close()

	data, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, 0, err
	}

	if res.StatusCode >= 500 {
		return data, res.StatusCode, fmt.Errorf("python agent service returned %d", res.StatusCode)
	}

	return data, res.StatusCode, nil
}

// Stream starts a request whose response body remains open for the caller to
// proxy. Unlike Post, it has no client-level timeout because essay generation
// may stream for several minutes. The request context still handles disconnects.
func (c *Client) Stream(ctx context.Context, path string, body []byte) (*http.Response, error) {
	req, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		c.baseURL+path,
		bytes.NewReader(body),
	)
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "text/event-stream")

	return c.streaming.Do(req)
}
