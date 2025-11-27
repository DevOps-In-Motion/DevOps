# Multi-Tenant Kubernetes Platform

This directory contains a reference implementation for automating multi-tenant namespace provisioning as a service on Kubernetes. This project demonstrates how to build a SaaS platform where each customer (tenant) gets isolated namespaces with network and resource separation, suitable for a 3-tier web application architecture.

## Overview

This project provides a complete automation framework for provisioning and managing tenant namespaces in Kubernetes. It includes:

- **Automated namespace provisioning** with RBAC, network policies, and resource quotas
- **gRPC-based microservices** for account management and job execution
- **Multi-tier isolation** (namespace, node pool, or cluster-level)
- **AWS integration** with IRSA (IAM Roles for Service Accounts) for secure cloud resource access
- **Ephemeral job execution** for tenant workloads

## Architecture

The platform consists of two main services:

1. **Account Provisioning Service** (`go-services/account-provisioning/`)
   - Creates and manages tenant namespaces
   - Provisions RBAC roles, network policies, resource quotas
   - Manages AWS IAM roles and S3 prefixes
   - Supports plan tiers (Free, Starter, Pro, Enterprise)

2. **MCP Job Service** (`go-services/mcp-job-service/`)
   - Manages ephemeral pods for tenant job execution
   - Handles job lifecycle (create, monitor, cancel)
   - Provides job logs and status tracking



## Cluster Personas

The platform defines four distinct personas with different access levels:

### Cluster Administrator - DevOps and IT
- Full cluster-wide access
- Manages the provisioning services
- Can create and delete tenant namespaces
- Manages cluster-level resources

### Tenant Administrator - 
- Full control within their tenant namespace
- Can deploy and manage applications
- Manages RBAC for tenant users
- Configure network policies (within tenant scope)

### Tenant Users - MCP Job Service, Acct Manager
- Standard users within tenant namespace
- Can deploy and manage workloads
- Limited to their organization's namespace
- Subject to resource quotas

### Tenant Viewers - Other resources
- Read-only access to tenant namespace
- Can view resources and logs
- Cannot modify or create resources

## Key Features

### Multi-Tier Isolation
- **Namespace-level**: Standard isolation (default)
- **Node Pool-level**: Dedicated node pools for enterprise customers
- **Cluster-level**: Dedicated clusters for regulated industries

### Resource Management
- Automatic resource quota assignment based on plan tier
- CPU and memory limits per tenant
- Limits on PVCs, services, deployments, and statefulsets
- Horizontal Pod Autoscaling support

### Network Isolation
- Network policies enforcing tenant isolation
- Pod-to-pod communication restrictions
- Egress controls for external access

### AWS Integration
- IRSA (IAM Roles for Service Accounts) for secure AWS access
- Automatic IAM role creation per tenant
- S3 prefix isolation for tenant data
- ECS task execution policies

### Job Execution
- Ephemeral pod creation for tenant workloads
- Job lifecycle management (create, monitor, cancel)
- Log aggregation and retrieval
- Callback webhook support

## Usage

### Prerequisites
- Kubernetes cluster (1.24+)
- Go 1.25+
- Buf CLI for protocol buffer code generation
- AWS EKS (for IRSA support)

### Building Services

```bash
cd go-services
./start.sh  # Generates gRPC code and builds services
```

### Deploying Manifests

The manifests in `manifests/` use environment variable substitution (e.g., `${TENANT_NAME}`). Apply them with your tenant-specific values:

```bash
export TENANT_NAME=customer123
envsubst < manifests/namespace.yaml | kubectl apply -f -
```

### API Examples

See `api/example-calls.js` for example API calls to:
- Create a new tenant account
- Submit MCP jobs for execution

## Service Definitions

The platform uses gRPC services defined in `go-services/saas/v1/services.proto`:

- **AccountProvisioningService**: CRUD operations for tenant accounts
- **MCPJobService**: Job lifecycle management
- **HealthService**: Health check endpoints

All services use mTLS for secure communication and are designed to be deployed as Kubernetes services.