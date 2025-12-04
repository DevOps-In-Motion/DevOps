package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"

	mcppkg "github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/pkg/mcp"
)

func main() {
	mcpURL := os.Getenv("MCP_SERVER_URL")
	if mcpURL == "" {
		mcpURL = "http://mcp-server:8080"
	}

	worker, err := mcppkg.NewWorker(mcpURL)
	if err != nil {
		log.Fatal(err)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	log.Println("Worker starting...")
	worker.Run(ctx)
}
