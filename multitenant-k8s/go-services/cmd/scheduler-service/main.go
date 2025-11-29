package main

import (
	"context"
	"log"
	"net/http"
	"os"

	connect "connectrpc.com/connect"

	schedv1 "github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/gen/proto/mcp-scheduler/v1"
	schedconnect "github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/gen/proto/mcp-scheduler/v1/mcpschedulerv1connect"
	"github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/pkg/schedulerservice"
)

// mcpJobHandler adapts schedulerservice.Service to the generated MCPJobService.
type mcpJobHandler struct {
	svc *schedulerservice.Service
}

func (h *mcpJobHandler) CreateJob(ctx context.Context, req *connect.Request[schedv1.CreateJobRequest]) (*connect.Response[schedv1.CreateJobResponse], error) {
	resp, err := h.svc.ScheduleJob(ctx, req.Msg)
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}
	return connect.NewResponse(resp), nil
}

// Other MCPJobService RPCs can be implemented later.
func (h *mcpJobHandler) GetJob(context.Context, *connect.Request[schedv1.GetJobRequest]) (*connect.Response[schedv1.GetJobResponse], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, nil)
}

func (h *mcpJobHandler) ListJobs(context.Context, *connect.Request[schedv1.ListJobsRequest]) (*connect.Response[schedv1.ListJobsResponse], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, nil)
}

func (h *mcpJobHandler) CancelJob(context.Context, *connect.Request[schedv1.CancelJobRequest]) (*connect.Response[schedv1.CancelJobResponse], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, nil)
}

func (h *mcpJobHandler) GetJobLogs(context.Context, *connect.Request[schedv1.GetJobLogsRequest]) (*connect.Response[schedv1.GetJobLogsResponse], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, nil)
}

func main() {
	// Wire scheduler with Redis + Kafka from environment.
	svc, err := schedulerservice.NewFromEnv()
	if err != nil {
		log.Fatalf("failed to create scheduler service: %v", err)
	}

	handler := &mcpJobHandler{svc: svc}

	mux := http.NewServeMux()
	path, hnd := schedconnect.NewMCPJobServiceHandler(handler)
	mux.Handle(path, hnd)

	addr := ":" + envOrDefault("SCHEDULER_SERVER_PORT", "8081")
	log.Printf("MCPJobService scheduler listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}

func envOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
