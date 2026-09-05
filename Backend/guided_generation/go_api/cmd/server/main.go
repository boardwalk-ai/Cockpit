package main

import (
	"log"
	"net/http"
	"os"
	"strconv"

	"github.com/boardwalk-ai/Cockpit/Backend/guided_generation/go_api/internal/api"
	"github.com/boardwalk-ai/Cockpit/Backend/guided_generation/go_api/internal/pythonclient"
	"github.com/boardwalk-ai/Cockpit/Backend/guided_generation/go_api/internal/store"
)

func main() {
	pythonURL := os.Getenv("PYTHON_AGENT_URL")
	if pythonURL == "" {
		pythonURL = "http://localhost:8201"
	}

	client := pythonclient.New(pythonURL)
	dataPath := os.Getenv("GUIDED_GENERATION_DATA_PATH")
	if dataPath == "" {
		dataPath = "data/guided_generation.json"
	}
	defaultCredits := 1000
	if configured := os.Getenv("DEFAULT_USER_CREDITS"); configured != "" {
		value, err := strconv.Atoi(configured)
		if err != nil || value < 0 {
			log.Fatal("DEFAULT_USER_CREDITS must be a non-negative integer")
		}
		defaultCredits = value
	}
	dataStore, err := store.New(dataPath, defaultCredits)
	if err != nil {
		log.Fatal(err)
	}
	server := api.NewServer(client, dataStore)

	listenAddress := os.Getenv("GO_API_ADDR")
	if listenAddress == "" {
		listenAddress = ":8200"
	}
	log.Printf("guided generation Go API listening on %s", listenAddress)
	if err := http.ListenAndServe(listenAddress, server.Handler()); err != nil {
		log.Fatal(err)
	}
}
