# MCP Kubernetes Jobs Architecture

## Overview

This implementation uses **Kubernetes Jobs** that process individual Kafka messages and exit. Each job contains both the MCP server and worker logic in a single process, optimized for job-based execution patterns.

## Architecture

```
┌─────────────┐         ┌──────────────────────┐
│   Kafka     │────────▶│   K8s Job (Pod)      │
│   Topic     │         │  ┌────────────────┐  │
└─────────────┘         │  │  MCP Worker    │  │
                        │  │  + MCP Logic   │  │
                        │  └────────────────┘  │
                        │   Processes 1 msg    │
                        │   Then exits         │
                        └──────────────────────┘
                                   │
                                   ▼
                             Job Completes
```

### How It Works

1. **Job Controller** watches Kafka for new messages
2. **Creates K8s Job** for each message (or batch)
3. **Job Pod starts**, reads assigned message from Kafka
4. **Processes message** using embedded MCP server logic
5. **Commits offset** and exits with success/failure code
6. **K8s cleans up** completed jobs based on TTL

## Why Jobs Instead of Long-Running Services?

### ✅ Benefits

1. **True Horizontal Scaling**
   - Unlimited parallel processing (1000+ jobs)
   - No connection pooling or HTTP overhead
   - Auto-scales based on Kafka lag

2. **Resource Efficiency**
   - Jobs only consume resources while processing
   - No idle workers waiting for messages
   - K8s reclaims resources immediately after completion

3. **Isolation**
   - Each message processed in clean environment
   - Failed jobs don't affect others
   - Easy to retry individual failures

4. **Cost Optimization**
   - Pay only for actual processing time
   - Perfect for bursty workloads
   - No over-provisioning needed

5. **Simplicity**
   - No HTTP server/client code needed
   - No service discovery or networking
   - All logic in one binary

## Code Structure

```
.
├── pkg/mcp/
│   └── job.go              # MCP job logic (all-in-one)
├── cmd/
│   ├── mcp-job/
│   │   └── main.go         # Job entrypoint
│   └── job-controller/
│       └── main.go         # Creates K8s jobs from Kafka
├── Dockerfile.job          # Job container
├── Dockerfile.controller   # Controller container
└── k8s/
    ├── job-template.yaml   # Job template
    └── controller.yaml     # Controller deployment
```

## Implementation

### pkg/mcp/job.go

```go
package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/modelcontextprotocol/go-sdk/mcp"
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
```

### cmd/mcp-job/main.go

```go
package main

import (
	"context"
	"log"
	"os"
	"strconv"

	mcppkg "your-module/pkg/mcp"
)

func main() {
	// K8s job passes partition and offset as env vars
	partition, _ := strconv.Atoi(os.Getenv("KAFKA_PARTITION"))
	offset, _ := strconv.ParseInt(os.Getenv("KAFKA_OFFSET"), 10, 64)

	ctx := context.Background()

	// Read the specific message assigned to this job
	messageValue, err := mcppkg.ReadSingleMessage(ctx, partition, offset)
	if err != nil {
		log.Fatalf("Failed to read message: %v", err)
	}

	// Process the message with MCP logic
	if err := mcppkg.ProcessMessage(ctx, messageValue); err != nil {
		log.Fatalf("Failed to process message: %v", err)
		os.Exit(1)
	}

	log.Println("Job completed successfully")
	os.Exit(0)
}
```

### cmd/job-controller/main.go

```go
package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/segmentio/kafka-go"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

func main() {
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Fatal(err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatal(err)
	}

	brokers := strings.Split(os.Getenv("KAFKA_BROKERS"), ",")
	topic := os.Getenv("KAFKA_TOPIC")
	groupID := os.Getenv("KAFKA_CONSUMER_GROUP")

	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers: brokers,
		GroupID: groupID,
		Topic:   topic,
	})
	defer reader.Close()

	ctx := context.Background()

	log.Println("Job controller started, watching for messages...")

	for {
		msg, err := reader.FetchMessage(ctx)
		if err != nil {
			log.Printf("Error fetching message: %v", err)
			time.Sleep(5 * time.Second)
			continue
		}

		// Create K8s Job for this message
		job := createJobSpec(msg.Partition, msg.Offset)
		
		_, err = clientset.BatchV1().Jobs("default").Create(ctx, job, metav1.CreateOptions{})
		if err != nil {
			log.Printf("Failed to create job: %v", err)
			continue
		}

		log.Printf("Created job for partition=%d offset=%d", msg.Partition, msg.Offset)

		// Commit the offset (job will handle actual processing)
		reader.CommitMessages(ctx, msg)
	}
}

func createJobSpec(partition int, offset int64) *batchv1.Job {
	ttl := int32(3600) // Clean up after 1 hour

	return &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{
			GenerateName: "mcp-job-",
			Namespace:    "default",
		},
		Spec: batchv1.JobSpec{
			TTLSecondsAfterFinished: &ttl,
			Template: corev1.PodTemplateSpec{
				Spec: corev1.PodSpec{
					RestartPolicy: corev1.RestartPolicyNever,
					Containers: []corev1.Container{
						{
							Name:  "mcp-job",
							Image: "your-registry/mcp-job:latest",
							Env: []corev1.EnvVar{
								{Name: "KAFKA_BROKERS", Value: os.Getenv("KAFKA_BROKERS")},
								{Name: "KAFKA_TOPIC", Value: os.Getenv("KAFKA_TOPIC")},
								{Name: "KAFKA_PARTITION", Value: fmt.Sprintf("%d", partition)},
								{Name: "KAFKA_OFFSET", Value: fmt.Sprintf("%d", offset)},
							},
							Resources: corev1.ResourceRequirements{
								Requests: corev1.ResourceList{
									corev1.ResourceCPU:    resource.MustParse("100m"),
									corev1.ResourceMemory: resource.MustParse("128Mi"),
								},
								Limits: corev1.ResourceList{
									corev1.ResourceCPU:    resource.MustParse("500m"),
									corev1.ResourceMemory: resource.MustParse("256Mi"),
								},
							},
						},
					},
				},
			},
		},
	}
}
```

## Kubernetes Configuration

### k8s/controller-deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mcp-job-controller
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mcp-job-controller
  template:
    metadata:
      labels:
        app: mcp-job-controller
    spec:
      serviceAccountName: mcp-job-controller
      containers:
      - name: controller
        image: your-registry/mcp-job-controller:latest
        env:
        - name: KAFKA_BROKERS
          value: "kafka:9092"
        - name: KAFKA_TOPIC
          value: "mcp-jobs"
        - name: KAFKA_CONSUMER_GROUP
          value: "mcp-job-controller"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: mcp-job-controller
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: mcp-job-creator
  namespace: default
rules:
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["create", "get", "list", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: mcp-job-controller-binding
  namespace: default
subjects:
- kind: ServiceAccount
  name: mcp-job-controller
  namespace: default
roleRef:
  kind: Role
  name: mcp-job-creator
  apiGroup: rbac.authorization.k8s.io
```

## Deployment

### Build and Push Images

```bash
# Build job image
docker build -f Dockerfile.job -t your-registry/mcp-job:latest .
docker push your-registry/mcp-job:latest

# Build controller image
docker build -f Dockerfile.controller -t your-registry/mcp-job-controller:latest .
docker push your-registry/mcp-job-controller:latest
```

### Deploy to K8s

```bash
# Deploy controller
kubectl apply -f k8s/controller-deployment.yaml

# Watch jobs being created
kubectl get jobs -w

# View job logs
kubectl logs job/mcp-job-abcd123
```

## Scaling & Performance

### Automatic Scaling

Jobs scale automatically based on Kafka messages:
- 1 message = 1 job
- 1000 messages = 1000 jobs (K8s permitting)

### Resource Limits

Control job resource usage:

```yaml
resources:
  requests:
    cpu: 100m      # Minimum guaranteed
    memory: 128Mi
  limits:
    cpu: 500m      # Maximum allowed
    memory: 256Mi
```

### Parallelism Control

Limit concurrent jobs if needed:

```yaml
# In controller code
spec:
  parallelism: 100          # Max 100 jobs running simultaneously
  completions: 1000         # Total jobs to complete
```

## Monitoring

### Key Metrics

- **Job Success Rate**: `kubectl get jobs --field-selector status.successful>0`
- **Job Failure Rate**: `kubectl get jobs --field-selector status.failed>0`
- **Average Duration**: Track from job creation to completion
- **Pending Jobs**: Jobs waiting for resources

### Troubleshooting

**Jobs stuck in Pending:**
```bash
kubectl describe job mcp-job-abcd123
# Check for resource constraints or quota limits
```

**Jobs failing:**
```bash
kubectl logs job/mcp-job-abcd123
# Check application errors in job logs
```

**Too many completed jobs:**
```bash
# Clean up completed jobs
kubectl delete jobs --field-selector status.successful=1
```

## Comparison: Jobs vs Services

| Aspect | K8s Jobs (This) | Long-Running Services (Previous) |
|--------|-----------------|----------------------------------|
| **Scaling** | Unlimited parallel jobs | Limited by worker replicas |
| **Resources** | Pay per message | Pay for idle time |
| **Isolation** | Full isolation per message | Shared process space |
| **Complexity** | Simple (no HTTP) | More complex (HTTP client/server) |
| **Cost** | Very efficient | Higher for bursty loads |
| **Latency** | Job startup overhead (~2-5s) | Immediate processing |

## Summary

This job-based architecture provides:
- ✅ True horizontal scalability (1000+ concurrent jobs)
- ✅ Resource efficiency (no idle workers)
- ✅ Clean isolation per message
- ✅ Simple codebase (no HTTP overhead)
- ✅ Perfect for bursty Kafka workloads
- ✅ Cost-optimized for cloud environments

The MCP logic runs **embedded in each job**, not as a separate server, making it perfect for Kubernetes Job patterns.