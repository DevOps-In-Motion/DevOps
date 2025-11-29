package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/pkg/schedulerservice"
	"github.com/segmentio/kafka-go"
)

type MCPServersConfig struct {
	MCPServers map[string]MCPServerDetails `json:"mcpServers"`
}

type MCPServerDetails struct {
	Command string   `json:"command"`
	Args    []string `json:"args"`
	EnvFile string   `json:"envFile"`
}

// ProcessSingleMessage reads one message from Kafka, processes it, and exits
func ProcessSingleMessage(ctx context.Context) error {
	brokers := strings.Split(os.Getenv("KAFKA_BROKERS"), ",")
	topic := os.Getenv("KAFKA_TOPIC")
	groupID := os.Getenv("KAFKA_CONSUMER_GROUP")

	if len(brokers) == 0 || topic == "" || groupID == "" {
		return fmt.Errorf("missing required environment variables")
	}

	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:        brokers,
		GroupID:        groupID,
		Topic:          topic,
		MinBytes:       1,
		MaxBytes:       10e6,
		CommitInterval: 0, // Manual commit
		StartOffset:    kafka.LastOffset,
	})
	defer reader.Close()

	log.Printf("Connecting to Kafka: brokers=%v topic=%s group=%s", brokers, topic, groupID)

	// Set timeout for fetching message
	fetchCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	// Fetch exactly ONE message
	msg, err := reader.FetchMessage(fetchCtx)
	if err != nil {
		return fmt.Errorf("failed to fetch message: %w", err)
	}

	log.Printf("Received message: partition=%d offset=%d", msg.Partition, msg.Offset)

	// Parse the scheduled job envelope
	var env schedulerservice.ScheduledJobEnvelope
	if err := json.Unmarshal(msg.Value, &env); err != nil {
		// Commit bad message to skip it
		if commitErr := reader.CommitMessages(ctx, msg); commitErr != nil {
			log.Printf("Failed to commit bad message: %v", commitErr)
		}
		return fmt.Errorf("failed to unmarshal job envelope: %w", err)
	}

	log.Printf("Processing job: id=%s type=%s", env.JobID, env.JobType)

	// Parse MCP configuration from payload
	var config MCPServersConfig
	if err := json.Unmarshal([]byte(env.Payload), &config); err != nil {
		if commitErr := reader.CommitMessages(ctx, msg); commitErr != nil {
			log.Printf("Failed to commit bad payload: %v", commitErr)
		}
		return fmt.Errorf("failed to parse MCP config: %w", err)
	}

	// Process each MCP server in the configuration
	for serverName, serverDetails := range config.MCPServers {
		log.Printf("Initializing MCP server: %s", serverName)

		if err := initializeServer(ctx, serverName, serverDetails); err != nil {
			// Don't commit - let Kafka retry
			return fmt.Errorf("failed to initialize server %s: %w", serverName, err)
		}

		log.Printf("Successfully initialized: %s", serverName)
	}

	// Commit offset only after successful processing
	if err := reader.CommitMessages(ctx, msg); err != nil {
		return fmt.Errorf("failed to commit offset: %w", err)
	}

	log.Printf("Job %s completed successfully", env.JobID)
	return nil
}

// initializeServer executes the MCP server initialization logic
func initializeServer(ctx context.Context, serverName string, details MCPServerDetails) error {
	log.Printf("Executing: %s %v", details.Command, details.Args)
	log.Printf("Environment file: %s", details.EnvFile)

	// TODO: Implement actual MCP server initialization
	// This might involve:
	// - Loading environment variables from EnvFile
	// - Spawning the command with args
	// - Waiting for initialization confirmation
	// - Health checking the server
	// - Returning success/failure

	// For now, simulate work
	time.Sleep(2 * time.Second)

	return nil
}
