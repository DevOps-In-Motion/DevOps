package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/pkg/schedulerservice"
	"github.com/segmentio/kafka-go"
)

// AutomationRunner defines how an MCP server executes a scheduled automation
// from the JSON payload produced by the scheduler.
type AutomationRunner interface {
	Run(ctx context.Context, env *schedulerservice.ScheduledJobEnvelope) error
}

// MCPWorker is a Kafka consumer that reads scheduled jobs and
// dispatches them to an AutomationRunner (your MCP automation server).
type MCPWorker struct {
	reader *kafka.Reader
	runner AutomationRunner
}

// NewMCPWorkerFromEnv wires an MCPWorker using environment variables:
//
//	KAFKA_BROKERS       - comma-separated list of brokers (host:port)
//	KAFKA_TOPIC         - topic name for MCP jobs
//	MCP_CONSUMER_GROUP  - Kafka consumer group ID for the MCP workers
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

// Run starts the MCP worker consume loop. It blocks until ctx is canceled
// or an unrecoverable error occurs.
func (w *MCPWorker) Run(ctx context.Context) error {
	for {
		msg, err := w.reader.ReadMessage(ctx)
		if err != nil {
			// Context cancellation is expected on shutdown.
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
			// You can add DLQ behavior here if desired.
			continue
		}
	}
}
