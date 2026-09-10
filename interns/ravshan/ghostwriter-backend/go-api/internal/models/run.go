package models

import (
	"sync"
	"time"
)

type RunStatus string

const (
	RunPending        RunStatus = "pending"
	RunRunning        RunStatus = "running"
	RunWaitingForUser RunStatus = "waiting_for_user"
	RunRevisionMode   RunStatus = "revision_mode"
	RunFinished       RunStatus = "finished"
	RunError          RunStatus = "error"
	RunCancelled      RunStatus = "cancelled"
)

type AgentEvent struct {
	Type             string           `json:"type"`
	Text             string           `json:"text,omitempty"`
	Chunk            string           `json:"chunk,omitempty"`
	ID               string           `json:"id,omitempty"`
	Title            string           `json:"title,omitempty"`
	Tool             string           `json:"tool,omitempty"`
	Args             any              `json:"args,omitempty"`
	Detail           string           `json:"detail,omitempty"`
	Summary          string           `json:"summary,omitempty"`
	Error            string           `json:"error,omitempty"`
	Retryable        bool             `json:"retryable,omitempty"`
	Field            string           `json:"field,omitempty"`
	Question         string           `json:"question,omitempty"`
	Options          []QuestionOption `json:"options,omitempty"`
	Suggestions      []string         `json:"suggestions,omitempty"`
	InputType        string           `json:"inputType,omitempty"`
	AllowCustom      bool             `json:"allowCustom,omitempty"`
	Sources          []QuestionSource `json:"sources,omitempty"`
	Patch            map[string]any   `json:"patch,omitempty"`
	PromptTokens     int              `json:"promptTokens,omitempty"`
	CompletionTokens int              `json:"completionTokens,omitempty"`
	TotalTokens      int              `json:"totalTokens,omitempty"`
	ExportDoc        any              `json:"exportDoc,omitempty"`
}

type QuestionOption struct {
	Label string `json:"label"`
	Value string `json:"value"`
}

type QuestionSource struct {
	URL            string `json:"url"`
	Title          string `json:"title,omitempty"`
	Publisher      string `json:"publisher,omitempty"`
	ContentPreview string `json:"contentPreview,omitempty"`
}

type Run struct {
	ID             string
	Draft          map[string]any
	Status         RunStatus
	CreatedAt      time.Time
	Finished       bool
	PendingField   string
	PauseRequested bool

	Events   chan AgentEvent
	Messages chan string
	Answers  chan Answer

	Mu sync.RWMutex
}

type Answer struct {
	Field string `json:"field"`
	Value any    `json:"value"`
}
