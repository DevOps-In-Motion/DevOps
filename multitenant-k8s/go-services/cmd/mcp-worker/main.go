package main

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/pkg/mcp"
	"github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/pkg/schedulerservice"
)

// simpleRunner is a placeholder AutomationRunner. Replace Run with real MCP automation.
type simpleRunner struct{}

func (r *simpleRunner) Run(ctx context.Context, env *schedulerservice.ScheduledJobEnvelope) error {
	// TODO: call your MCP server/automation engine here using env fields.
	log.Printf("Executing automation: job_id=%s org=%s type=%s", env.JobID, env.OrganizationID, env.JobType)
	return nil
}

func main() {
	runner := &simpleRunner{}

	worker, err := mcp.NewMCPWorkerFromEnv(runner)
	if err != nil {
		log.Fatalf("failed to create MCP worker: %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Allow graceful shutdown via SIGINT/SIGTERM.
	go func() {
		ch := make(chan os.Signal, 1)
		// signal.Notify(ch, syscall.SIGINT, syscall.SIGTERM)
		<-ch
		cancel()
	}()

	log.Printf("MCP worker starting consume loop")
	if err := worker.Run(ctx); err != nil && ctx.Err() == nil {
		log.Fatalf("worker error: %v", err)
	}

	// Give logs a moment to flush.
	time.Sleep(100 * time.Millisecond)
}
