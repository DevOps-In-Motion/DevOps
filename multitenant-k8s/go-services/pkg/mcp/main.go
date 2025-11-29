package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/modelcontextprotocol/go-sdk/mcp"

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
	ServerName string           `json:"serverName" jsonschema:"required,description=Name of the MCP server to initialize"`
	Config     MCPServersConfig `json:"config" jsonschema:"required,description=MCP server configuration"`
}

type ServerInitializeOutput struct {
	ServerDetails MCPServerDetails `json:"serverDetails" jsonschema:"description=Configuration details for the initialized server"`
	Status        string           `json:"status" jsonschema:"description=Initialization status"`
}

func handleServerInitialize(
	ctx context.Context,
	req *mcp.CallToolRequest,
	args ServerInitializeArgs,
) (*mcp.CallToolResult, ServerInitializeOutput, error) {
	if len(args.Config.MCPServers) == 0 {
		return nil, ServerInitializeOutput{}, fmt.Errorf("no MCP servers found in configuration")
	}

	serverDetails, exists := args.Config.MCPServers[args.ServerName]
	if !exists {
		return nil, ServerInitializeOutput{}, fmt.Errorf("server %s not found in configuration", args.ServerName)
	}

	output := ServerInitializeOutput{
		ServerDetails: serverDetails,
		Status:        "initialized",
	}

	return nil, output, nil
}

func CreateMCPServer(name, version string) *mcp.Server {
	return mcp.NewServer(&mcp.Implementation{
		Name:    name,
		Version: version,
	}, nil)
}

func RegisterServerTools(server *mcp.Server) {
	mcp.AddTool(server, &mcp.Tool{
		Name:        "server_initialize",
		Description: "Initialize an MCP server configuration from Kafka message",
	}, handleServerInitialize)
}

type AutomationRunner interface {
	Run(ctx context.Context, env *schedulerservice.ScheduledJobEnvelope) error
}

type MCPWorker struct {
	reader *kafka.Reader
	runner AutomationRunner
}

func NewMCPWorkerFromEnv(runner AutomationRunner) (*MCPWorker, error) {
	if runner == nil {
		return nil, fmt.Errorf("runner must not be nil")
	}

	brokersEnv := os.Getenv("KAFKA_BROKERS")
	topic := os.Getenv("KAFKA_TOPIC")
	groupID := os.Getenv("MCP_CONSUMER_GROUP")

	var brokers []string
	for _, b := range strings.Split(brokersEnv, ",") {
		b = strings.TrimSpace(b)
		if b != "" {
			brokers = append(brokers, b)
		}
	}

	if len(brokers) == 0 {
		return nil, fmt.Errorf("KAFKA_BROKERS must not be empty")
	}
	if topic == "" {
		return nil, fmt.Errorf("KAFKA_TOPIC must not be empty")
	}
	if groupID == "" {
		return nil, fmt.Errorf("MCP_CONSUMER_GROUP must not be empty")
	}

	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers: brokers,
		GroupID: groupID,
		Topic:   topic,
	})

	return &MCPWorker{
		reader: reader,
		runner: runner,
	}, nil
}

func (w *MCPWorker) Run(ctx context.Context) error {
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		msg, err := w.reader.ReadMessage(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			return fmt.Errorf("failed to read message from kafka: %w", err)
		}

		var env schedulerservice.ScheduledJobEnvelope
		if err := json.Unmarshal(msg.Value, &env); err != nil {
			log.Printf("failed to unmarshal scheduled job payload: %v", err)
			continue
		}

		if err := w.runner.Run(ctx, &env); err != nil {
			log.Printf("automation runner error for job %s: %v", env.JobID, err)
			continue
		}

		log.Printf("automation runner success for job %s", env.JobID)
	}
}

func (w *MCPWorker) Close() error {
	return w.reader.Close()
}
