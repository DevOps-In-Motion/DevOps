// mcp-job-service/server.go
package main

import (
	"context"
	"log"
	"net"

	saasv1 "github.com/devops-in-motion/saas-services/gen/go/saas/v1"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/protobuf/types/known/timestamppb"
	"k8s.io/client-go/kubernetes"
)

type MCPJobServer struct {
	saasv1.UnimplementedMCPJobServiceServer
	clientset *kubernetes.Clientset
	repo      *JobRepository
	config    *MCPJobConfig
}

func (s *MCPJobServer) CreateJob(ctx context.Context, req *saasv1.CreateJobRequest) (*saasv1.CreateJobResponse, error) {
	log.Printf("Creating MCP job for org: %s", req.OrganizationId)

	// Your implementation from previous artifacts
	// ...

	return &saasv1.CreateJobResponse{
		JobId:               jobID,
		OrganizationId:      req.OrganizationId,
		Status:              saasv1.JobStatus_JOB_STATUS_PENDING,
		PodName:             podName,
		Namespace:           namespace,
		CreatedAt:           timestamppb.Now(),
		EstimatedTtlSeconds: 300,
	}, nil
}

func main() {
	// Load mTLS certificates
	creds, err := credentials.NewServerTLSFromFile(
		"/etc/certs/server.crt",
		"/etc/certs/server.key",
	)
	if err != nil {
		log.Fatalf("Failed to load certificates: %v", err)
	}

	// Create gRPC server with mTLS
	server := grpc.NewServer(
		grpc.Creds(creds),
	)

	// Register service
	jobServer := &MCPJobServer{
		// Initialize dependencies...
	}
	saasv1.RegisterMCPJobServiceServer(server, jobServer)

	// Start server
	lis, err := net.Listen("tcp", ":8081")
	if err != nil {
		log.Fatalf("Failed to listen: %v", err)
	}

	log.Println("MCP Job Service listening on :8081")
	if err := server.Serve(lis); err != nil {
		log.Fatalf("Failed to serve: %v", err)
	}
}
