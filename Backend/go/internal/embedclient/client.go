package embedclient

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type Client struct {
	base   string
	http   *http.Client
}

func New(base string) *Client {
	return &Client{
		base: base,
		http: &http.Client{Timeout: 180 * time.Second},
	}
}

func (c *Client) Embed(texts []string) ([][]float64, error) {
	if len(texts) == 0 {
		return nil, nil
	}
	body, _ := json.Marshal(map[string]any{"texts": texts})
	resp, err := c.http.Post(c.base+"/embed", "application/json", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("embed HTTP %d", resp.StatusCode)
	}
	var out struct {
		Vectors [][]float64 `json:"vectors"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	return out.Vectors, nil
}
