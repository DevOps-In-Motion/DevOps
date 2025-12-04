package main

import (
	"context"
	"log"
	"net/http"
	"os"

	connect "connectrpc.com/connect"

	acctv1 "github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/gen/proto/acct-management/v1"
	acctconnect "github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/gen/proto/acct-management/v1/acctmanagementv1connect"
	"github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/pkg/accountservice"
)

// accountHandler adapts pkg/accountservice.Service to the generated Connect handler interface.
type accountHandler struct {
	svc *accountservice.Service
}

func (h *accountHandler) CreateAccount(ctx context.Context, req *connect.Request[acctv1.CreateAccountRequest]) (*connect.Response[acctv1.CreateAccountResponse], error) {
	r := req.Msg

	result, err := h.svc.ProvisionAccount(ctx, r.GetOrganizationId(), r.GetOrganizationType(), r.GetPlanTier(), r.GetS3Bucket())
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}

	resp := &acctv1.CreateAccountResponse{
		OrganizationId:   result.OrganizationID,
		Namespace:        result.Namespace,
		OrganizationType: r.GetOrganizationType(),
		PlanTier:         r.GetPlanTier(),
		IamRoleArn:       result.IAMRoleARN,
		S3Bucket:         result.S3Bucket,
		S3Prefix:         result.S3Prefix,
		ResourceQuota:    result.ResourceQuota,
		Status:           "ACTIVE",
	}

	return connect.NewResponse(resp), nil
}

// The rest of the RPCs can be wired later; for now return Unimplemented.
func (h *accountHandler) GetAccount(context.Context, *connect.Request[acctv1.GetAccountRequest]) (*connect.Response[acctv1.GetAccountResponse], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, nil)
}

func (h *accountHandler) UpdateAccount(context.Context, *connect.Request[acctv1.UpdateAccountRequest]) (*connect.Response[acctv1.UpdateAccountResponse], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, nil)
}

func (h *accountHandler) DeleteAccount(ctx context.Context, req *connect.Request[acctv1.DeleteAccountRequest]) (*connect.Response[acctv1.DeleteAccountResponse], error) {
	if err := h.svc.DeleteAccount(ctx, req.Msg.GetOrganizationId()); err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}
	resp := &acctv1.DeleteAccountResponse{
		OrganizationId: req.Msg.GetOrganizationId(),
		Status:         "DELETED",
	}
	return connect.NewResponse(resp), nil
}

func (h *accountHandler) ListAccounts(context.Context, *connect.Request[acctv1.ListAccountsRequest]) (*connect.Response[acctv1.ListAccountsResponse], error) {
	return nil, connect.NewError(connect.CodeUnimplemented, nil)
}

func main() {
	// Wire the domain service from environment.
	cfg := accountservice.Config{
		KubeConfigPath: os.Getenv("KUBECONFIG"),
		AWSRegion:      os.Getenv("AWS_REGION"),
		ClusterARN:     os.Getenv("CLUSTER_ARN"),
	}

	svc, err := accountservice.New(cfg)
	if err != nil {
		log.Fatalf("failed to create account service: %v", err)
	}

	h := &accountHandler{svc: svc}

	mux := http.NewServeMux()
	path, handler := acctconnect.NewAccountProvisioningServiceHandler(h)
	mux.Handle(path, handler)

	addr := ":" + envOrDefault("ACCOUNT_SERVER_PORT", "8080")
	log.Printf("AccountProvisioningService listening on %s", addr)
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
