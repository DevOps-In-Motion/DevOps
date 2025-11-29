package auto

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/pkg/mcp"
	"github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/pkg/schedulerservice"
)

type Runner struct {
	mcpClient *mcp.MCPClient
}

func NewRunner(mcpServerURL string) *Runner {
	return &Runner{
		mcpClient: mcp.NewMCPClient(mcpServerURL),
	}
}

func (r *Runner) Run(ctx context.Context, env *schedulerservice.ScheduledJobEnvelope) error {
	log.Printf("Processing job %s: %s", env.JobID, env.JobType)

	var config mcp.MCPServersConfig
	if err := json.Unmarshal([]byte(env.Payload), &config); err != nil {
		return fmt.Errorf("failed to parse MCP config from payload: %w", err)
	}

	for serverName := range config.MCPServers {
		output, err := r.mcpClient.InitializeServer(ctx, serverName, config)
		if err != nil {
			return fmt.Errorf("failed to initialize server %s: %w", serverName, err)
		}

		log.Printf("Server %s initialized: %s", serverName, output.Message)
	}

	return nil
}
