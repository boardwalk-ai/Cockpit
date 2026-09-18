package store

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

var ErrNotFound = errors.New("not found")
var ErrInsufficientCredits = errors.New("insufficient credits")
var ErrFolderNotFound = errors.New("folder not found")

type Message struct {
	Role string `json:"role"`
	Text string `json:"text"`
}

type Thread struct {
	ID            string  `json:"id"`
	UID           string  `json:"uid"`
	Title         string  `json:"title"`
	Status        string  `json:"status"`
	FolderID      *string `json:"folderId"`
	RunID         string  `json:"runId"`
	Prompt        string  `json:"prompt"`
	WordCount     *int    `json:"wordCount"`
	CitationStyle *string `json:"citationStyle"`
	CreatedAt     string  `json:"createdAt"`
	UpdatedAt     string  `json:"updatedAt"`
}

type ThreadFull struct {
	Thread
	Essay    *string         `json:"essay"`
	Messages []Message       `json:"messages"`
	RunState json.RawMessage `json:"runState"`
}

type CreateThread struct {
	RunID         string  `json:"runId"`
	Prompt        string  `json:"prompt"`
	Title         string  `json:"title"`
	FolderID      *string `json:"folderId"`
	WordCount     *int    `json:"wordCount"`
	CitationStyle *string `json:"citationStyle"`
}

type UpdateThread struct {
	Title         *string
	Status        *string
	FolderID      *string
	FolderSet     bool
	Essay         *string
	EssaySet      bool
	Messages      *[]Message
	WordCount     *int
	WordCountSet  bool
	CitationStyle *string
	CitationSet   bool
	RunState      json.RawMessage
	RunStateSet   bool
}

type Folder struct {
	ID        string `json:"id"`
	UID       string `json:"uid"`
	Name      string `json:"name"`
	Color     string `json:"color"`
	Order     int64  `json:"order"`
	CreatedAt string `json:"createdAt"`
}

type DeductionResult struct {
	Charge      int `json:"charge"`
	OctoCredits int `json:"octo_credits"`
}

type state struct {
	Threads    map[string]ThreadFull      `json:"threads"`
	Folders    map[string]Folder          `json:"folders"`
	Credits    map[string]int             `json:"credits"`
	Deductions map[string]DeductionResult `json:"deductions"`
}

type Store struct {
	mu             sync.RWMutex
	path           string
	defaultCredits int
	data           state
}

func New(path string, defaultCredits int) (*Store, error) {
	s := &Store{
		path:           path,
		defaultCredits: defaultCredits,
		data: state{
			Threads:    map[string]ThreadFull{},
			Folders:    map[string]Folder{},
			Credits:    map[string]int{},
			Deductions: map[string]DeductionResult{},
		},
	}
	if path == "" {
		return s, nil
	}

	bytes, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return s, nil
	}
	if err != nil {
		return nil, err
	}
	if len(bytes) > 0 {
		if err := json.Unmarshal(bytes, &s.data); err != nil {
			return nil, err
		}
	}
	s.ensureMaps()
	return s, nil
}

func (s *Store) ensureMaps() {
	if s.data.Threads == nil {
		s.data.Threads = map[string]ThreadFull{}
	}
	if s.data.Folders == nil {
		s.data.Folders = map[string]Folder{}
	}
	if s.data.Credits == nil {
		s.data.Credits = map[string]int{}
	}
	if s.data.Deductions == nil {
		s.data.Deductions = map[string]DeductionResult{}
	}
}

func (s *Store) persistLocked() error {
	if s.path == "" {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(s.path), 0o755); err != nil {
		return err
	}
	bytes, err := json.MarshalIndent(s.data, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(s.path, bytes, 0o600)
}

func (s *Store) ListThreads(uid string) []Thread {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := []Thread{}
	for _, thread := range s.data.Threads {
		if thread.UID == uid {
			result = append(result, thread.Thread)
		}
	}
	sort.Slice(result, func(i, j int) bool { return result[i].UpdatedAt > result[j].UpdatedAt })
	return result
}

func (s *Store) CreateThread(uid string, input CreateThread) (ThreadFull, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if input.FolderID != nil && !s.folderExistsLocked(uid, *input.FolderID) {
		return ThreadFull{}, ErrFolderNotFound
	}
	now := time.Now().UTC().Format(time.RFC3339Nano)
	title := input.Title
	if title == "" {
		title = "Untitled essay"
	}
	thread := ThreadFull{
		Thread: Thread{
			ID:            newID(),
			UID:           uid,
			Title:         title,
			Status:        "running",
			FolderID:      input.FolderID,
			RunID:         input.RunID,
			Prompt:        input.Prompt,
			WordCount:     input.WordCount,
			CitationStyle: input.CitationStyle,
			CreatedAt:     now,
			UpdatedAt:     now,
		},
		Messages: []Message{},
		RunState: json.RawMessage("null"),
	}
	s.data.Threads[thread.ID] = thread
	return thread, s.persistLocked()
}

func (s *Store) GetThread(uid, id string) (ThreadFull, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	thread, ok := s.data.Threads[id]
	if !ok || thread.UID != uid {
		return ThreadFull{}, ErrNotFound
	}
	return thread, nil
}

func (s *Store) UpdateThread(uid, id string, patch UpdateThread) (ThreadFull, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	thread, ok := s.data.Threads[id]
	if !ok || thread.UID != uid {
		return ThreadFull{}, ErrNotFound
	}
	if patch.FolderSet && patch.FolderID != nil && !s.folderExistsLocked(uid, *patch.FolderID) {
		return ThreadFull{}, ErrFolderNotFound
	}
	if patch.Title != nil {
		thread.Title = *patch.Title
	}
	if patch.Status != nil {
		thread.Status = *patch.Status
	}
	if patch.FolderSet {
		thread.FolderID = patch.FolderID
	}
	if patch.EssaySet {
		thread.Essay = patch.Essay
	}
	if patch.Messages != nil {
		thread.Messages = *patch.Messages
	}
	if patch.WordCountSet {
		thread.WordCount = patch.WordCount
	}
	if patch.CitationSet {
		thread.CitationStyle = patch.CitationStyle
	}
	if patch.RunStateSet {
		thread.RunState = patch.RunState
	}
	thread.UpdatedAt = time.Now().UTC().Format(time.RFC3339Nano)
	s.data.Threads[id] = thread
	return thread, s.persistLocked()
}

func (s *Store) DeleteThread(uid, id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	thread, ok := s.data.Threads[id]
	if !ok || thread.UID != uid {
		return ErrNotFound
	}
	delete(s.data.Threads, id)
	return s.persistLocked()
}

func (s *Store) ListFolders(uid string) []Folder {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := []Folder{}
	for _, folder := range s.data.Folders {
		if folder.UID == uid {
			result = append(result, folder)
		}
	}
	sort.Slice(result, func(i, j int) bool {
		if result[i].Order == result[j].Order {
			return result[i].CreatedAt < result[j].CreatedAt
		}
		return result[i].Order < result[j].Order
	})
	return result
}

func (s *Store) CreateFolder(uid, name, color string, order int64) (Folder, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	folder := Folder{
		ID:        newID(),
		UID:       uid,
		Name:      name,
		Color:     color,
		Order:     order,
		CreatedAt: time.Now().UTC().Format(time.RFC3339Nano),
	}
	s.data.Folders[folder.ID] = folder
	return folder, s.persistLocked()
}

func (s *Store) UpdateFolder(uid, id string, name, color *string, order *int64) (Folder, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	folder, ok := s.data.Folders[id]
	if !ok || folder.UID != uid {
		return Folder{}, ErrNotFound
	}
	if name != nil {
		folder.Name = *name
	}
	if color != nil {
		folder.Color = *color
	}
	if order != nil {
		folder.Order = *order
	}
	s.data.Folders[id] = folder
	return folder, s.persistLocked()
}

func (s *Store) DeleteFolder(uid, id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	folder, ok := s.data.Folders[id]
	if !ok || folder.UID != uid {
		return ErrNotFound
	}
	delete(s.data.Folders, id)
	for threadID, thread := range s.data.Threads {
		if thread.UID == uid && thread.FolderID != nil && *thread.FolderID == id {
			thread.FolderID = nil
			thread.UpdatedAt = time.Now().UTC().Format(time.RFC3339Nano)
			s.data.Threads[threadID] = thread
		}
	}
	return s.persistLocked()
}

func (s *Store) Balance(uid string) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	balance, ok := s.data.Credits[uid]
	if !ok {
		balance = s.defaultCredits
		s.data.Credits[uid] = balance
		if err := s.persistLocked(); err != nil {
			return 0, err
		}
	}
	return balance, nil
}

func (s *Store) Deduct(uid string, amount int, idempotencyKey string) (DeductionResult, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if idempotencyKey != "" {
		if previous, ok := s.data.Deductions[uid+":"+idempotencyKey]; ok {
			return previous, nil
		}
	}
	balance, ok := s.data.Credits[uid]
	if !ok {
		balance = s.defaultCredits
	}
	if balance < amount {
		return DeductionResult{}, ErrInsufficientCredits
	}
	result := DeductionResult{Charge: amount, OctoCredits: balance - amount}
	s.data.Credits[uid] = result.OctoCredits
	if idempotencyKey != "" {
		s.data.Deductions[uid+":"+idempotencyKey] = result
	}
	return result, s.persistLocked()
}

func (s *Store) folderExistsLocked(uid, id string) bool {
	folder, ok := s.data.Folders[id]
	return ok && folder.UID == uid
}

func newID() string {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err == nil {
		return hex.EncodeToString(bytes)
	}
	return time.Now().UTC().Format("20060102150405.000000000")
}
