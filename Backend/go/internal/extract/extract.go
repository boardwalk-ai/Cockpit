package extract

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"
)

const minChars = 20
const minPerPage = 40

func Usable(text string, pages int) bool {
	if utf8.RuneCountInString(text) < minChars {
		return false
	}
	n := pages
	if n < 1 {
		n = 1
	}
	return utf8.RuneCountInString(text)/n >= minPerPage
}

func Chunk(text string, size, overlap int) []string {
	words := strings.Fields(text)
	if len(words) == 0 {
		return nil
	}
	step := size - overlap
	if step < 1 {
		step = 1
	}
	var out []string
	for start := 0; start < len(words); start += step {
		end := start + size
		if end > len(words) {
			end = len(words)
		}
		out = append(out, strings.Join(words[start:end], " "))
		if end >= len(words) {
			break
		}
	}
	return out
}

type Hirara struct {
	URL, Token string
	http       *http.Client
}

func NewHirara(url, token string) *Hirara {
	return &Hirara{URL: url, Token: token, http: &http.Client{Timeout: 120 * time.Second}}
}

func (h *Hirara) Call(name string, args map[string]any) (map[string]any, error) {
	payload, _ := json.Marshal(map[string]any{"name": name, "arguments": args})
	req, err := http.NewRequest(http.MethodPost, strings.TrimRight(h.URL, "/")+"/call", bytes.NewReader(payload))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	if h.Token != "" {
		req.Header.Set("Authorization", "Bearer "+h.Token)
	}
	resp, err := h.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	var out map[string]any
	if err := json.Unmarshal(body, &out); err != nil {
		return nil, err
	}
	return out, nil
}

func Extract(filename, mime string, data []byte, hirara *Hirara) (string, error) {
	name := strings.ToLower(filename)
	if strings.HasPrefix(mime, "text/") || strings.HasSuffix(name, ".txt") || strings.HasSuffix(name, ".md") {
		return string(data), nil
	}
	if mime == "application/pdf" || strings.HasSuffix(name, ".pdf") {
		if hirara == nil {
			return "", nil
		}
		b64 := base64.StdEncoding.EncodeToString(data)
		res, err := hirara.Call("pdf_read", map[string]any{"pdf_base64": b64})
		text := ""
		if err == nil {
			text, _ = res["text"].(string)
			text = strings.TrimSpace(text)
		}
		pages := 1
		if Usable(text, pages) {
			return text, nil
		}
		ocr, err := hirara.Call("ocr_read", map[string]any{"file_base64": b64, "languages": []string{"en"}})
		if err == nil {
			if t, _ := ocr["text"].(string); strings.TrimSpace(t) != "" {
				return strings.TrimSpace(t), nil
			}
			if t, _ := ocr["markdown"].(string); strings.TrimSpace(t) != "" {
				return strings.TrimSpace(t), nil
			}
		}
		return text, nil
	}
	if hirara == nil {
		return "", nil
	}
	b64 := base64.StdEncoding.EncodeToString(data)
	if strings.HasPrefix(mime, "image/") {
		ocr, err := hirara.Call("ocr_read", map[string]any{"file_base64": b64, "languages": []string{"en"}})
		if err != nil {
			return "", err
		}
		if t, _ := ocr["text"].(string); t != "" {
			return strings.TrimSpace(t), nil
		}
		if t, _ := ocr["markdown"].(string); t != "" {
			return strings.TrimSpace(t), nil
		}
		return "", nil
	}
	res, err := hirara.Call("office_read", map[string]any{"file_base64": b64, "filename": filename})
	if err != nil {
		return "", err
	}
	if t, _ := res["markdown"].(string); t != "" {
		return strings.TrimSpace(t), nil
	}
	if t, _ := res["text"].(string); t != "" {
		return strings.TrimSpace(t), nil
	}
	return "", nil
}
