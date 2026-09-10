package store

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/google/uuid"
)

type Folder struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"createdAt"`
}

type Thread struct {
	ID            string           `json:"id"`
	FolderID      string           `json:"folderId,omitempty"`
	RunID         string           `json:"runId,omitempty"`
	Title         string           `json:"title"`
	Prompt        string           `json:"prompt"`
	Status        string           `json:"status"`
	Essay         string           `json:"essay,omitempty"`
	Bibliography  string           `json:"bibliography,omitempty"`
	CitationStyle string           `json:"citationStyle,omitempty"`
	WordCount     int              `json:"wordCount,omitempty"`
	Sources       []map[string]any `json:"sources,omitempty"`
	CreatedAt     time.Time        `json:"createdAt"`
	UpdatedAt     time.Time        `json:"updatedAt"`
}

type WorkspaceState struct {
	SessionName string   `json:"sessionName"`
	Credits     int      `json:"credits"`
	Folders     []Folder `json:"folders"`
	Threads     []Thread `json:"threads"`
}

type WorkspaceStore struct {
	mu    sync.Mutex
	path  string
	state WorkspaceState
}

func NewWorkspaceStore(path string) *WorkspaceStore {
	s := &WorkspaceStore{
		path: path,
		state: WorkspaceState{
			SessionName: "GUEST",
			Credits:     2067,
			Folders:     []Folder{},
			Threads:     []Thread{},
		},
	}

	_ = s.load()

	return s
}

func (s *WorkspaceStore) load() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	data, err := os.ReadFile(s.path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}

	return json.Unmarshal(data, &s.state)
}

func (s *WorkspaceStore) persistLocked() error {
	if err := os.MkdirAll(filepath.Dir(s.path), 0o755); err != nil {
		return err
	}

	data, err := json.MarshalIndent(s.state, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(s.path, data, 0o644)
}

func (s *WorkspaceStore) Snapshot() WorkspaceState {
	s.mu.Lock()
	defer s.mu.Unlock()

	return s.state
}

func (s *WorkspaceStore) UseCredits(amount int) int {
	s.mu.Lock()
	defer s.mu.Unlock()

	if amount < 0 {
		amount = 0
	}

	if amount > s.state.Credits {
		s.state.Credits = 0
	} else {
		s.state.Credits -= amount
	}

	_ = s.persistLocked()

	return s.state.Credits
}

func (s *WorkspaceStore) CreateFolder(name string) Folder {
	s.mu.Lock()
	defer s.mu.Unlock()

	folder := Folder{
		ID:        uuid.NewString(),
		Name:      name,
		CreatedAt: time.Now(),
	}

	s.state.Folders = append(s.state.Folders, folder)
	_ = s.persistLocked()

	return folder
}

func (s *WorkspaceStore) SaveThread(thread Thread) Thread {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()

	if thread.ID == "" {
		thread.ID = uuid.NewString()
		thread.CreatedAt = now
	}

	thread.UpdatedAt = now

	for i := range s.state.Threads {
		if s.state.Threads[i].ID == thread.ID {
			s.state.Threads[i] = thread
			_ = s.persistLocked()
			return thread
		}
	}

	s.state.Threads = append([]Thread{thread}, s.state.Threads...)
	_ = s.persistLocked()

	return thread
}
