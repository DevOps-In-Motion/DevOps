package accountservice

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/iam"
	"github.com/aws/aws-sdk-go-v2/service/iam/types"

	acctv1 "github.com/DevOps-In-Motion/DevOps/multitenant-k8s/go-services/gen/proto/acct-management/v1"

	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

// Service holds dependencies for the account provisioning service
type Service struct {
	k8sClient  kubernetes.Interface
	iamClient  *iam.Client
	awsConfig  aws.Config
	clusterARN string // EKS cluster ARN for IRSA
}

// Config holds configuration for the service
type Config struct {
	KubeConfigPath string // Path to kubeconfig file (empty for in-cluster)
	AWSRegion      string // AWS region
	ClusterARN     string // EKS cluster ARN for IAM role trust policy
}

// New creates a new account service with AWS and K8s clients
func New(cfg Config) (*Service, error) {
	// Initialize Kubernetes client
	k8sClient, err := newK8sClient(cfg.KubeConfigPath)
	if err != nil {
		return nil, fmt.Errorf("failed to create k8s client: %w", err)
	}

	// Initialize AWS config
	awsCfg, err := awsconfig.LoadDefaultConfig(context.Background(),
		awsconfig.WithRegion(cfg.AWSRegion),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to load AWS config: %w", err)
	}

	// Create IAM client
	iamClient := iam.NewFromConfig(awsCfg)

	return &Service{
		k8sClient:  k8sClient,
		iamClient:  iamClient,
		awsConfig:  awsCfg,
		clusterARN: cfg.ClusterARN,
	}, nil
}

// newK8sClient creates a Kubernetes client
func newK8sClient(kubeconfigPath string) (kubernetes.Interface, error) {
	var config *rest.Config
	var err error

	if kubeconfigPath == "" {
		// Use in-cluster config (when running in a pod)
		config, err = rest.InClusterConfig()
	} else {
		// Use kubeconfig file (for local development)
		config, err = clientcmd.BuildConfigFromFlags("", kubeconfigPath)
	}

	if err != nil {
		return nil, err
	}

	return kubernetes.NewForConfig(config)
}

// ============================================================================
// Kubernetes Operations
// ============================================================================

// createK8sNamespace creates a namespace for the tenant
func (s *Service) createK8sNamespace(ctx context.Context, orgID string, tier acctv1.PlanTier) (string, error) {
	namespaceName := fmt.Sprintf("tenant-%s", orgID)

	namespace := &corev1.Namespace{
		ObjectMeta: metav1.ObjectMeta{
			Name: namespaceName,
			Labels: map[string]string{
				"tenant-id":  orgID,
				"plan-tier":  tier.String(),
				"managed-by": "account-provisioning-service",
				"created-at": time.Now().Format(time.RFC3339),
			},
			Annotations: map[string]string{
				"organization-id": orgID,
				"description":     fmt.Sprintf("Tenant namespace for organization %s", orgID),
			},
		},
	}

	_, err := s.k8sClient.CoreV1().Namespaces().Create(ctx, namespace, metav1.CreateOptions{})
	if err != nil {
		return "", fmt.Errorf("failed to create namespace: %w", err)
	}

	return namespaceName, nil
}

// applyResourceQuota applies resource quotas to the namespace based on plan tier
func (s *Service) applyResourceQuota(ctx context.Context, namespace string, tier acctv1.PlanTier) (*acctv1.ResourceQuota, error) {
	// Define quotas per plan tier
	quotaSpecs := map[acctv1.PlanTier]*acctv1.ResourceQuota{
		acctv1.PlanTier_PLAN_TIER_FREE: {
			RequestsCpu:     "2",
			RequestsMemory:  "4Gi",
			LimitsCpu:       "4",
			LimitsMemory:    "8Gi",
			MaxPvcs:         5,
			MaxServices:     10,
			MaxDeployments:  5,
			MaxStatefulsets: 2,
		},
		acctv1.PlanTier_PLAN_TIER_STARTER: {
			RequestsCpu:     "5",
			RequestsMemory:  "10Gi",
			LimitsCpu:       "10",
			LimitsMemory:    "20Gi",
			MaxPvcs:         10,
			MaxServices:     20,
			MaxDeployments:  10,
			MaxStatefulsets: 5,
		},
		acctv1.PlanTier_PLAN_TIER_PRO: {
			RequestsCpu:     "20",
			RequestsMemory:  "40Gi",
			LimitsCpu:       "40",
			LimitsMemory:    "80Gi",
			MaxPvcs:         30,
			MaxServices:     50,
			MaxDeployments:  25,
			MaxStatefulsets: 10,
		},
		acctv1.PlanTier_PLAN_TIER_ENTERPRISE: {
			RequestsCpu:     "100",
			RequestsMemory:  "200Gi",
			LimitsCpu:       "200",
			LimitsMemory:    "400Gi",
			MaxPvcs:         100,
			MaxServices:     200,
			MaxDeployments:  100,
			MaxStatefulsets: 50,
		},
	}

	quotaSpec, ok := quotaSpecs[tier]
	if !ok {
		return nil, fmt.Errorf("unknown plan tier: %v", tier)
	}

	// Create K8s ResourceQuota object
	resourceQuota := &corev1.ResourceQuota{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "tenant-quota",
			Namespace: namespace,
			Labels: map[string]string{
				"plan-tier": tier.String(),
			},
		},
		Spec: corev1.ResourceQuotaSpec{
			Hard: corev1.ResourceList{
				"requests.cpu":            resource.MustParse(quotaSpec.RequestsCpu),
				"requests.memory":         resource.MustParse(quotaSpec.RequestsMemory),
				"limits.cpu":              resource.MustParse(quotaSpec.LimitsCpu),
				"limits.memory":           resource.MustParse(quotaSpec.LimitsMemory),
				"persistentvolumeclaims":  resource.MustParse(fmt.Sprintf("%d", quotaSpec.MaxPvcs)),
				"services":                resource.MustParse(fmt.Sprintf("%d", quotaSpec.MaxServices)),
				"count/deployments.apps":  resource.MustParse(fmt.Sprintf("%d", quotaSpec.MaxDeployments)),
				"count/statefulsets.apps": resource.MustParse(fmt.Sprintf("%d", quotaSpec.MaxStatefulsets)),
			},
		},
	}

	_, err := s.k8sClient.CoreV1().ResourceQuotas(namespace).Create(ctx, resourceQuota, metav1.CreateOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to create resource quota: %w", err)
	}

	return quotaSpec, nil
}

// applyNetworkPolicy creates a network policy for tenant isolation
func (s *Service) applyNetworkPolicy(ctx context.Context, namespace string) error {
	// TODO: Implement network policy for tenant isolation
	// This would restrict ingress/egress to only allowed namespaces
	return nil
}

// createServiceAccount creates a Kubernetes service account with IRSA annotations
func (s *Service) createServiceAccount(ctx context.Context, namespace, orgID, iamRoleARN string) error {
	serviceAccount := &corev1.ServiceAccount{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "tenant-sa",
			Namespace: namespace,
			Annotations: map[string]string{
				// IRSA annotation for EKS
				"eks.amazonaws.com/role-arn": iamRoleARN,
			},
			Labels: map[string]string{
				"tenant-id": orgID,
			},
		},
	}

	_, err := s.k8sClient.CoreV1().ServiceAccounts(namespace).Create(ctx, serviceAccount, metav1.CreateOptions{})
	if err != nil {
		return fmt.Errorf("failed to create service account: %w", err)
	}

	return nil
}

// createRBAC creates RBAC roles and bindings for the tenant
func (s *Service) createRBAC(ctx context.Context, namespace, orgID string) error {
	// Admin role for tenant admins
	adminRole := &rbacv1.Role{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "tenant-admin",
			Namespace: namespace,
		},
		Rules: []rbacv1.PolicyRule{
			{
				APIGroups: []string{"*"},
				Resources: []string{"*"},
				Verbs:     []string{"*"},
			},
		},
	}

	_, err := s.k8sClient.RbacV1().Roles(namespace).Create(ctx, adminRole, metav1.CreateOptions{})
	if err != nil {
		return fmt.Errorf("failed to create admin role: %w", err)
	}

	// User role for regular users (read-only on most resources)
	userRole := &rbacv1.Role{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "tenant-user",
			Namespace: namespace,
		},
		Rules: []rbacv1.PolicyRule{
			{
				APIGroups: []string{"", "apps"},
				Resources: []string{"pods", "services", "deployments"},
				Verbs:     []string{"get", "list", "watch"},
			},
		},
	}

	_, err = s.k8sClient.RbacV1().Roles(namespace).Create(ctx, userRole, metav1.CreateOptions{})
	if err != nil {
		return fmt.Errorf("failed to create user role: %w", err)
	}

	return nil
}

// ============================================================================
// AWS IAM Operations
// ============================================================================

// createIAMRole creates an IAM role for the tenant with IRSA trust policy
func (s *Service) createIAMRole(ctx context.Context, orgID string) (string, error) {
	roleName := fmt.Sprintf("tenant-%s-role", orgID)

	// Create trust policy for IRSA (IAM Roles for Service Accounts)
	trustPolicy := map[string]interface{}{
		"Version": "2012-10-17",
		"Statement": []map[string]interface{}{
			{
				"Effect": "Allow",
				"Principal": map[string]interface{}{
					"Federated": s.clusterARN,
				},
				"Action": "sts:AssumeRoleWithWebIdentity",
				"Condition": map[string]interface{}{
					"StringEquals": map[string]string{
						// This would need to be customized per cluster's OIDC provider
						// Format: oidc.eks.region.amazonaws.com/id/CLUSTER_ID:sub
						fmt.Sprintf("%s:sub", s.clusterARN): fmt.Sprintf("system:serviceaccount:tenant-%s:tenant-sa", orgID),
					},
				},
			},
		},
	}

	trustPolicyJSON, err := json.Marshal(trustPolicy)
	if err != nil {
		return "", fmt.Errorf("failed to marshal trust policy: %w", err)
	}

	// Create IAM role
	createRoleOutput, err := s.iamClient.CreateRole(ctx, &iam.CreateRoleInput{
		RoleName:                 aws.String(roleName),
		AssumeRolePolicyDocument: aws.String(string(trustPolicyJSON)),
		Description:              aws.String(fmt.Sprintf("IAM role for tenant %s", orgID)),
		Tags: []types.Tag{
			{
				Key:   aws.String("tenant-id"),
				Value: aws.String(orgID),
			},
			{
				Key:   aws.String("managed-by"),
				Value: aws.String("account-provisioning-service"),
			},
		},
	})

	if err != nil {
		return "", fmt.Errorf("failed to create IAM role: %w", err)
	}

	return *createRoleOutput.Role.Arn, nil
}

// attachS3Policy attaches a policy to the IAM role for S3 access
func (s *Service) attachS3Policy(ctx context.Context, roleName, s3Bucket, orgID string) error {
	// Create inline policy for S3 access (scoped to tenant's prefix)
	policyDocument := map[string]interface{}{
		"Version": "2012-10-17",
		"Statement": []map[string]interface{}{
			{
				"Effect": "Allow",
				"Action": []string{
					"s3:GetObject",
					"s3:PutObject",
					"s3:DeleteObject",
					"s3:ListBucket",
				},
				"Resource": []string{
					fmt.Sprintf("arn:aws:s3:::%s/orgs/%s/*", s3Bucket, orgID),
					fmt.Sprintf("arn:aws:s3:::%s", s3Bucket),
				},
				"Condition": map[string]interface{}{
					"StringLike": map[string]string{
						"s3:prefix": fmt.Sprintf("orgs/%s/*", orgID),
					},
				},
			},
		},
	}

	policyJSON, err := json.Marshal(policyDocument)
	if err != nil {
		return fmt.Errorf("failed to marshal policy: %w", err)
	}

	_, err = s.iamClient.PutRolePolicy(ctx, &iam.PutRolePolicyInput{
		RoleName:       aws.String(roleName),
		PolicyName:     aws.String("tenant-s3-access"),
		PolicyDocument: aws.String(string(policyJSON)),
	})

	if err != nil {
		return fmt.Errorf("failed to attach S3 policy: %w", err)
	}

	return nil
}

// ============================================================================
// High-Level Provisioning Methods
// ============================================================================

// ProvisionAccount creates all resources for a new tenant account
func (s *Service) ProvisionAccount(ctx context.Context, orgID string, orgType acctv1.OrganizationType, tier acctv1.PlanTier, s3Bucket string) (*AccountProvisioningResult, error) {
	result := &AccountProvisioningResult{
		OrganizationID: orgID,
	}

	// 1. Create Kubernetes namespace
	namespace, err := s.createK8sNamespace(ctx, orgID, tier)
	if err != nil {
		return nil, fmt.Errorf("failed to create namespace: %w", err)
	}
	result.Namespace = namespace

	// 2. Apply resource quotas
	quota, err := s.applyResourceQuota(ctx, namespace, tier)
	if err != nil {
		// Cleanup namespace on failure
		s.k8sClient.CoreV1().Namespaces().Delete(ctx, namespace, metav1.DeleteOptions{})
		return nil, fmt.Errorf("failed to apply quota: %w", err)
	}
	result.ResourceQuota = quota

	// 3. Create IAM role
	iamRoleARN, err := s.createIAMRole(ctx, orgID)
	if err != nil {
		// Cleanup namespace on failure
		s.k8sClient.CoreV1().Namespaces().Delete(ctx, namespace, metav1.DeleteOptions{})
		return nil, fmt.Errorf("failed to create IAM role: %w", err)
	}
	result.IAMRoleARN = iamRoleARN

	// 4. Attach S3 policy
	if s3Bucket != "" {
		roleName := fmt.Sprintf("tenant-%s-role", orgID)
		if err := s.attachS3Policy(ctx, roleName, s3Bucket, orgID); err != nil {
			// Cleanup on failure
			s.cleanupResources(ctx, orgID, namespace, roleName)
			return nil, fmt.Errorf("failed to attach S3 policy: %w", err)
		}
		result.S3Bucket = s3Bucket
		result.S3Prefix = fmt.Sprintf("orgs/%s", orgID)
	}

	// 5. Create service account with IRSA
	if err := s.createServiceAccount(ctx, namespace, orgID, iamRoleARN); err != nil {
		s.cleanupResources(ctx, orgID, namespace, fmt.Sprintf("tenant-%s-role", orgID))
		return nil, fmt.Errorf("failed to create service account: %w", err)
	}

	// 6. Create RBAC roles
	if err := s.createRBAC(ctx, namespace, orgID); err != nil {
		s.cleanupResources(ctx, orgID, namespace, fmt.Sprintf("tenant-%s-role", orgID))
		return nil, fmt.Errorf("failed to create RBAC: %w", err)
	}

	// 7. Apply network policies (optional)
	if err := s.applyNetworkPolicy(ctx, namespace); err != nil {
		// Non-fatal, just log
		fmt.Printf("Warning: failed to apply network policy: %v\n", err)
	}

	return result, nil
}

// cleanupResources removes resources on provisioning failure
func (s *Service) cleanupResources(ctx context.Context, orgID, namespace, roleName string) {
	// Delete namespace (cascades to all resources in it)
	s.k8sClient.CoreV1().Namespaces().Delete(ctx, namespace, metav1.DeleteOptions{})

	// Delete IAM role and attached policies
	s.iamClient.DeleteRolePolicy(ctx, &iam.DeleteRolePolicyInput{
		RoleName:   aws.String(roleName),
		PolicyName: aws.String("tenant-s3-access"),
	})
	s.iamClient.DeleteRole(ctx, &iam.DeleteRoleInput{
		RoleName: aws.String(roleName),
	})
}

// DeleteAccount removes all resources for a tenant
func (s *Service) DeleteAccount(ctx context.Context, orgID string) error {
	namespace := fmt.Sprintf("tenant-%s", orgID)
	roleName := fmt.Sprintf("tenant-%s-role", orgID)

	// Delete namespace (cascades to all K8s resources)
	err := s.k8sClient.CoreV1().Namespaces().Delete(ctx, namespace, metav1.DeleteOptions{})
	if err != nil {
		return fmt.Errorf("failed to delete namespace: %w", err)
	}

	// Delete IAM role policies
	s.iamClient.DeleteRolePolicy(ctx, &iam.DeleteRolePolicyInput{
		RoleName:   aws.String(roleName),
		PolicyName: aws.String("tenant-s3-access"),
	})

	// Delete IAM role
	_, err = s.iamClient.DeleteRole(ctx, &iam.DeleteRoleInput{
		RoleName: aws.String(roleName),
	})
	if err != nil {
		return fmt.Errorf("failed to delete IAM role: %w", err)
	}

	return nil
}

// AccountProvisioningResult holds the result of account provisioning
type AccountProvisioningResult struct {
	OrganizationID string
	Namespace      string
	IAMRoleARN     string
	S3Bucket       string
	S3Prefix       string
	ResourceQuota  *acctv1.ResourceQuota
}
