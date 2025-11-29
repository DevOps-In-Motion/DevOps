package main

import (
	"context"
	"log"
	"os"

	mcppkg "github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/pkg/mcp"
)

func main() {
	log.Println("MCP Job starting...")

	ctx := context.Background()

	if err := mcppkg.ProcessSingleMessage(ctx); err != nil {
		log.Printf("Job failed: %v", err)
		os.Exit(1)
	}

	log.Println("Job completed successfully")
	os.Exit(0)
}
