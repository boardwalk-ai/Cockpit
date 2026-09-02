package store

import (
	"sync"

	"ghostwriter-backend/go-api/internal/models"
)

type RunStore struct {
	mu   sync.RWMutex
	runs map[string]*models.Run
}

func NewRunStore() *RunStore {
	return &RunStore{
		runs: make(map[string]*models.Run),
	}
}

func (s *RunStore) Create(run *models.Run) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.runs[run.ID] = run
}

func (s *RunStore) Get(id string) (*models.Run, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	run, ok := s.runs[id]
	return run, ok
}

func (s *RunStore) Delete(id string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	delete(s.runs, id)
}
