package store

import (
	"encoding/json"
	"path/filepath"
	"testing"
)

func TestPersistenceFoldersThreadsAndCredits(t *testing.T) {
	path := filepath.Join(t.TempDir(), "guided-generation.json")
	s, err := New(path, 500)
	if err != nil {
		t.Fatal(err)
	}

	folder, err := s.CreateFolder("user-1", "Research", "#123456", 1)
	if err != nil {
		t.Fatal(err)
	}
	wordCount := 1200
	citation := "APA"
	thread, err := s.CreateThread("user-1", CreateThread{
		RunID:         "run-1",
		Prompt:        "Write about energy",
		FolderID:      &folder.ID,
		WordCount:     &wordCount,
		CitationStyle: &citation,
	})
	if err != nil {
		t.Fatal(err)
	}

	status := "finished"
	essay := "Finished essay"
	updated, err := s.UpdateThread("user-1", thread.ID, UpdateThread{
		Status:      &status,
		Essay:       &essay,
		EssaySet:    true,
		RunState:    json.RawMessage(`{"savedAt":"now"}`),
		RunStateSet: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if updated.Essay == nil || *updated.Essay != essay {
		t.Fatalf("essay was not saved: %#v", updated.Essay)
	}

	first, err := s.Deduct("user-1", 125, "run-1:word")
	if err != nil {
		t.Fatal(err)
	}
	second, err := s.Deduct("user-1", 125, "run-1:word")
	if err != nil {
		t.Fatal(err)
	}
	if first.OctoCredits != 375 || second.OctoCredits != 375 {
		t.Fatalf("idempotent deduction failed: %#v %#v", first, second)
	}

	reloaded, err := New(path, 0)
	if err != nil {
		t.Fatal(err)
	}
	saved, err := reloaded.GetThread("user-1", thread.ID)
	if err != nil || saved.Status != "finished" {
		t.Fatalf("thread did not reload: %#v %v", saved, err)
	}
	balance, err := reloaded.Balance("user-1")
	if err != nil || balance != 375 {
		t.Fatalf("credits did not reload: %d %v", balance, err)
	}

	if err := reloaded.DeleteFolder("user-1", folder.ID); err != nil {
		t.Fatal(err)
	}
	unfiled, err := reloaded.GetThread("user-1", thread.ID)
	if err != nil || unfiled.FolderID != nil {
		t.Fatalf("deleting a folder did not unfile its thread: %#v %v", unfiled, err)
	}
}

func TestUserIsolationAndInsufficientCredits(t *testing.T) {
	s, err := New("", 10)
	if err != nil {
		t.Fatal(err)
	}
	folder, err := s.CreateFolder("user-1", "Private", "#000", 1)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpdateFolder("user-2", folder.ID, nil, nil, nil); err != ErrNotFound {
		t.Fatalf("expected user isolation, got %v", err)
	}
	if _, err := s.Deduct("user-1", 11, ""); err != ErrInsufficientCredits {
		t.Fatalf("expected insufficient credits, got %v", err)
	}
}
