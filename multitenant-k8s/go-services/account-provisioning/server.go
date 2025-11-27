// account-provisioning/server.go
package main

import (
	"context"
	"log"
	"net"

	saasv1 "github.com/devops-in-motion/saas-services/gen/go/saas/v1"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type AccountProvisioningServer struct {
	saasv1.UnimplementedAccountProvisioningServiceServer
	provisioner *TenantProvisioner
	iamService  *IAMService
	repo        *OrganizationRepository
}

func (s *AccountProvisioningServer) CreateAccount(ctx context.Context, req *saasv1.CreateAccountRequest) (*saasv1.CreateAccountResponse, error) {
	log.Printf("Creating account for org: %s", req.OrganizationId)

	// Your implementation from previous artifacts
	// ...

	return &saasv1.CreateAccountResponse{
		OrganizationId:          req.OrganizationId,
		Namespace:               namespace,
		OrganizationType:        req.OrganizationType,
		PlanTier:                req.PlanTier,
		IamRoleArn:              iamRole.ARN,
		S3Prefix:                s3Prefix,
		ResourceQuota:           quota,
		Status:                  "active",
		CreatedAt:               timestamppb.Now(),
		ProvisioningTimeSeconds: duration.Seconds(),
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
	accountServer := &AccountProvisioningServer{
		// Initialize dependencies...
	}
	saasv1.RegisterAccountProvisioningServiceServer(server, accountServer)

	// Start server
	lis, err := net.Listen("tcp", ":8080")
	if err != nil {
		log.Fatalf("Failed to listen: %v", err)
	}

	log.Println("Account Provisioning Service listening on :8080")
	if err := server.Serve(lis); err != nil {
		log.Fatalf("Failed to serve: %v", err)
	}
}
