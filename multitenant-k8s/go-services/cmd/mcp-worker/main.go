package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	mcppkg "github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/pkg/mcp"
	"github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/pkg/schedulerservice"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/segmentio/kafka-go"
)

func main() {
	log.Println("MCP Job starting...")

	ctx := context.Background()

	// Read message from Kafka
	messageValue, err := readKafkaMessage(ctx)
	if err != nil {
		log.Fatalf("Failed to read Kafka message: %v", err)
	}

	// Parse the message to get config
	config, err := parseMessage(messageValue)
	if err != nil {
		log.Fatalf("Failed to parse message: %v", err)
	}

	log.Printf("Processing config with %d servers", len(config.Servers))

	// Create and run MCP server
	server := mcppkg.CreateMCPServer()

	// Run the MCP server over SSE transport
	transport := &mcp.SSETransport{}

	if err := server.Run(ctx, transport); err != nil {
		log.Fatalf("MCP server failed: %v", err)
	}

	log.Println("MCP Job completed successfully")
	os.Exit(0)
}

func readKafkaMessage(ctx context.Context) ([]byte, error) {
	brokers := strings.Split(os.Getenv("KAFKA_BROKERS"), ",")
	topic := os.Getenv("KAFKA_TOPIC")
	groupID := os.Getenv("KAFKA_CONSUMER_GROUP")

	if len(brokers) == 0 || topic == "" || groupID == "" {
		return nil, fmt.Errorf("missing required environment variables")
	}

	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:        brokers,
		GroupID:        groupID,
		Topic:          topic,
		CommitInterval: 0,
	})
	defer reader.Close()

	log.Printf("Reading from Kafka: brokers=%v topic=%s group=%s", brokers, topic, groupID)

	fetchCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	msg, err := reader.FetchMessage(fetchCtx)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch message: %w", err)
	}

	log.Printf("Received message: partition=%d offset=%d", msg.Partition, msg.Offset)

	// Commit the message
	if err := reader.CommitMessages(ctx, msg); err != nil {
		log.Printf("Warning: failed to commit message: %v", err)
	}

	return msg.Value, nil
}

func parseMessage(messageValue []byte) (*mcppkg.MCPServersConfig, error) {
	var env schedulerservice.ScheduledJobEnvelope
	if err := json.Unmarshal(messageValue, &env); err != nil {
		return nil, fmt.Errorf("failed to unmarshal job envelope: %w", err)
	}

	log.Printf("Job ID: %s, Type: %s", env.JobID, env.JobType)

	var configJSON string
	if env.Payload != "" {
		configJSON = env.Payload
	} else if configStr, ok := env.Parameters["config"].(string); ok {
		configJSON = configStr
	} else {
		return nil, fmt.Errorf("no config found in payload or parameters")
	}

	var config mcppkg.MCPServersConfig
	if err := json.Unmarshal([]byte(configJSON), &config); err != nil {
		return nil, fmt.Errorf("failed to parse MCP config: %w", err)
	}

	return &config, nil
}
