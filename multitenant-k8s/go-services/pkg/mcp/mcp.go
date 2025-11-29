package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/pkg/schedulerservice"
	"github.com/segmentio/kafka-go"
)

// ExampleMCPServersConfigJSON demonstrates an example configuration for a MariaDB MCP server process.
// This is the expected JSON structure:
//
// {
//   "mcpServers": {
//     "MariaDB_Server": {
//       "command": "uv",
//       "args": [
//         "--directory",
//         "path/to/mariadb-mcp-server/",
//         "run",
//         "server.py"
//       ],
//       "envFile": "path/to/mcp-server-mariadb-vector/.env"
//     }
//   }
// }

type MCPServersConfig struct {
	MCPServers map[string]MCPServerDetails `json:"mcpServers"`
}

type MCPServerDetails struct {
	Command string   `json:"command"`
	Args    []string `json:"args"`
	EnvFile string   `json:"envFile"`
}

type ServerInitializeArgs struct {
	ServerName string           `json:"serverName"`
	Config     MCPServersConfig `json:"config"`
}

type ServerInitializeOutput struct {
	ServerDetails MCPServerDetails `json:"serverDetails"`
	Status        string           `json:"status"`
}

// ProcessMessage handles a single Kafka message using MCP logic
func ProcessMessage(ctx context.Context, messageValue []byte) error {
	var env schedulerservice.ScheduledJobEnvelope
	if err := json.Unmarshal(messageValue, &env); err != nil {
		return fmt.Errorf("failed to unmarshal job: %w", err)
	}

	var config MCPServersConfig
	if err := json.Unmarshal([]byte(env.Payload), &config); err != nil {
		return fmt.Errorf("failed to parse config: %w", err)
	}

	// Process each server in the config
	for serverName, serverDetails := range config.MCPServers {
		log.Printf("Initializing server: %s", serverName)

		// Execute MCP logic directly (no HTTP call needed)
		output, err := initializeServer(ctx, serverName, serverDetails, config)
		if err != nil {
			return fmt.Errorf("failed to initialize %s: %w", serverName, err)
		}

		log.Printf("Server %s: %s", serverName, output.Status)
	}

	log.Printf("Job %s completed successfully", env.JobID)
	return nil
}

// initializeServer executes the MCP server initialization logic
func initializeServer(
	ctx context.Context,
	serverName string,
	serverDetails MCPServerDetails,
	config MCPServersConfig,
) (*ServerInitializeOutput, error) {
	// Your actual MCP server logic here
	// This runs directly in the job, no HTTP needed

	output := &ServerInitializeOutput{
		ServerDetails: serverDetails,
		Status:        "initialized",
	}

	return output, nil
}

// ReadSingleMessage reads exactly one message from Kafka partition
func ReadSingleMessage(ctx context.Context, partition int, offset int64) ([]byte, error) {
	brokers := os.Getenv("KAFKA_BROKERS")
	topic := os.Getenv("KAFKA_TOPIC")

	conn, err := kafka.DialLeader(ctx, "tcp", brokers, topic, partition)
	if err != nil {
		return nil, fmt.Errorf("failed to dial leader: %w", err)
	}
	defer conn.Close()

	conn.SetReadDeadline(time.Now().Add(10 * time.Second))

	batch := conn.ReadBatch(1, 10e6)
	defer batch.Close()

	msg := make([]byte, 0)
	_, err = batch.Read(msg)
	if err != nil {
		return nil, fmt.Errorf("failed to read message: %w", err)
	}

	return msg, nil
}
