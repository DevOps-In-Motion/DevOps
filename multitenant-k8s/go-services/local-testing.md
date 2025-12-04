# MCP Hybrid Architecture

## Overview

This implementation uses a **hybrid architecture** that separates the MCP (Model Context Protocol) server from Kafka workers. This design provides scalability, reliability, and clear separation of concerns for production workloads.

## Architecture

```
┌─────────────┐         ┌──────────────┐         ┌─────────────┐
│   Kafka     │────────▶│ Kafka Worker │────────▶│ MCP Server  │
│   Topic     │         │  (Multiple)  │  HTTP   │  (Single)   │
└─────────────┘         └──────────────┘         └─────────────┘
                              │                         │
                              │                         │
                        ┌─────▼─────┐            ┌─────▼─────┐
                        │ Process   │            │ Execute   │
                        │ Messages  │            │ Tools     │
                        └───────────┘            └───────────┘
```

### Components

**1. MCP Server (Single Instance)**
- Runs as an HTTP service using SSE (Server-Sent Events) transport
- Exposes MCP tools via HTTP endpoint
- Handles tool execution requests from workers
- Stateless and scalable (can run multiple replicas behind load balancer)

**2. Kafka Workers (Multiple Instances)**
- Consume messages from Kafka topic
- Parse job payloads containing MCP configurations
- Make HTTP requests to MCP server to execute tools
- Commit offsets after successful processing
- Scale horizontally based on message volume

## Why This Architecture?

### ✅ Benefits

1. **Independent Scaling**
   - Scale workers based on Kafka lag
   - Scale MCP server based on CPU/memory usage
   - Each component scales independently

2. **Reliability**
   - Worker crashes don't affect MCP server
   - MCP server restarts don't lose Kafka messages
   - Failed jobs can be retried via Kafka consumer groups

3. **Simplicity**
   - Single MCP server handles all tool logic
   - Workers are simple Kafka consumers
   - Clear separation of concerns

4. **Observability**
   - Separate logs and metrics for each component
   - Easy to monitor Kafka lag, worker throughput, and server load
   - Can trace requests from Kafka message → Worker → MCP Server

### ❌ What This Solves

- **No stdio in containers**: MCP stdio transport requires interactive terminals, which don't work in containerized environments
- **No blocking operations**: Kafka consumers can't block on stdin/stdout
- **Clean deployment**: Each component can be deployed, scaled, and monitored independently

## Code Structure

```
.
├── pkg/mcp/
│   └── mcp.go              # Single file with all MCP logic
├── cmd/
│   ├── mcp-server/
│   │   └── main.go         # MCP server entrypoint
│   └── kafka-worker/
│       └── main.go         # Kafka worker entrypoint
├── Dockerfile.server       # MCP server container
├── Dockerfile.worker       # Kafka worker container
└── docker-compose.yml      # Local development setup
```

## How It Works

### 1. Message Flow

```json
{
  "jobID": "job-123",
  "jobType": "server-init",
  "payload": "{\"mcpServers\":{\"MariaDB_Server\":{\"command\":\"uv\",\"args\":[\"--directory\",\"path/to/server\",\"run\",\"server.py\"],\"envFile\":\"path/to/.env\"}}}"
}
```

### 2. Worker Processing

1. Worker reads message from Kafka
2. Unmarshals `ScheduledJobEnvelope`
3. Parses `MCPServersConfig` from payload
4. For each server in config:
   - Makes HTTP POST to MCP server
   - Calls `server_initialize` tool
   - Receives initialization result
5. Commits Kafka offset on success
6. Logs result

### 3. MCP Server Execution

1. Receives HTTP POST at `/message` endpoint
2. Extracts tool name and arguments
3. Executes `handleServerInitialize` function
4. Returns JSON result to worker
5. Worker processes response

## Configuration

### Environment Variables

**MCP Server:**
```bash
PORT=8080  # HTTP server port
```

**Kafka Worker:**
```bash
KAFKA_BROKERS=kafka:9092           # Comma-separated broker list
KAFKA_TOPIC=mcp-jobs               # Topic to consume from
MCP_CONSUMER_GROUP=mcp-workers     # Consumer group ID
MCP_SERVER_URL=http://mcp-server:8080  # MCP server endpoint
```

## Running Locally

### Using Docker Compose

```bash
# Start all services
docker-compose up --build

# Scale workers
docker-compose up --scale kafka-worker=5

# View logs
docker-compose logs -f kafka-worker
docker-compose logs -f mcp-server
```

### Standalone

**Terminal 1 - MCP Server:**
```bash
cd cmd/mcp-server
go run main.go
```

**Terminal 2 - Kafka Worker:**
```bash
export KAFKA_BROKERS=localhost:9092
export KAFKA_TOPIC=mcp-jobs
export MCP_CONSUMER_GROUP=mcp-workers
export MCP_SERVER_URL=http://localhost:8080

cd cmd/kafka-worker
go run main.go
```

## Production Deployment

### Kubernetes

```bash
# Deploy MCP server
kubectl apply -f k8s/mcp-server-deployment.yaml

# Deploy workers (starts with 3 replicas)
kubectl apply -f k8s/kafka-worker-deployment.yaml

# Scale workers based on load
kubectl scale deployment kafka-worker --replicas=10
```

### Monitoring

**Key Metrics:**

- **Kafka Workers**
  - Consumer lag
  - Messages processed per second
  - Error rate
  - Processing latency

- **MCP Server**
  - HTTP request rate
  - Tool execution time
  - Error rate
  - Active connections

## Adding New Tools

To add a new MCP tool:

1. **Define input/output types:**
```go
type MyToolArgs struct {
    Param string `json:"param" jsonschema:"required"`
}

type MyToolOutput struct {
    Result string `json:"result"`
}
```

2. **Implement handler:**
```go
func handleMyTool(
    ctx context.Context,
    req *mcp.CallToolRequest,
    args MyToolArgs,
) (*mcp.CallToolResult, MyToolOutput, error) {
    // Your logic here
    return nil, MyToolOutput{Result: "success"}, nil
}
```

3. **Register in CreateServer:**
```go
mcp.AddTool(server, &mcp.Tool{
    Name:        "my_tool",
    Description: "Does something useful",
}, handleMyTool)
```

4. **Add client method (optional):**
```go
func (c *Client) CallMyTool(ctx context.Context, param string) (*MyToolOutput, error) {
    // Call the tool via HTTP
}
```

## Troubleshooting

### Worker can't connect to MCP server

**Symptom:** `connection refused` errors in worker logs

**Solution:**
- Verify `MCP_SERVER_URL` is correct
- Check MCP server is running: `curl http://mcp-server:8080/health`
- Verify network connectivity between services

### Messages not being processed

**Symptom:** Kafka lag increasing, no worker logs

**Solution:**
- Check worker is running: `docker-compose ps kafka-worker`
- Verify Kafka configuration is correct
- Check consumer group: `kafka-consumer-groups --describe --group mcp-workers`

### Tool execution failures

**Symptom:** Worker logs show tool errors

**Solution:**
- Check MCP server logs for detailed error
- Verify JSON payload structure matches `MCPServersConfig`
- Ensure required fields are present in message

## Performance Tuning

### Worker Scaling

Scale based on Kafka consumer lag:

```bash
# If lag > 1000 messages
kubectl scale deployment kafka-worker --replicas=10

# If lag < 100 messages
kubectl scale deployment kafka-worker --replicas=2
```

### MCP Server Scaling

Scale based on CPU/memory:

```bash
# Horizontal scaling
kubectl scale deployment mcp-server --replicas=3

# Vertical scaling
kubectl set resources deployment mcp-server \
  --limits=cpu=1000m,memory=512Mi \
  --requests=cpu=500m,memory=256Mi
```


This architecture provides:
- ✅ Clean separation between message consumption and tool execution
- ✅ Independent scaling of workers and server
- ✅ Production-ready error handling and logging
- ✅ Container-friendly design (no stdio dependencies)
- ✅ Simple codebase with minimal complexity

For questions or issues, refer to the [MCP Go SDK documentation](https://github.com/modelcontextprotocol/go-sdk).