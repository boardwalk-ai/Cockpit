package main

import (
	"log"
	"net/http"
	"os"

	"ghostwriter-backend/go-api/internal/api"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	server := api.NewServer()

	log.Printf("GhostWriter Go API listening on :%s", port)

	if err := http.ListenAndServe(":"+port, server.Routes()); err != nil {
		log.Fatal(err)
	}
}
