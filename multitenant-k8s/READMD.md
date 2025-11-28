# Multi-Tenant Kubernetes Platform

This repository contains a reference solution for automating multi-tenant SaaS infrastructure in Kubernetes. It enables you to provision and manage fully isolated tenant environments—using namespaces, node pools, or clusters—complete with network and resource separation. The platform is designed for 3-tier and other modern cloud-native SaaS architectures.

## Overview

This project is a complete automation stack for the lifecycle of SaaS tenancy on Kubernetes, featuring:

- **Automated namespace and tenant infrastructure provisioning** (RBAC, network policy, quotas, etc.)
- **Modular gRPC microservices** for account creation, multi-cluster job scheduling, distributed locking, rate limiting, and health checks
- **Multi-level isolation:** support for namespace, node pool, or dedicated cluster per tenant
- **AWS EKS integration** with IRSA for tenant-scoped cloud access (e.g., IAM, S3)
- **Ephemeral workload management** and pluggable job runners
- **OpenAPI documentation and pluggable frontends**

## Architecture

The core platform services are organized in `go-services/` and defined via protocol buffers. Current microservices include:

1. **Account Provisioning Service** (`go-services/proto/acct-creation/v1/accts.proto`)
   - Automates namespace/infra creation (RBAC, quotas, etc.)
   - Manages AWS IAM roles, S3 prefixes per org
   - Supports tiered plans (Free → Enterprise)

2. **MCP Job Service** (`go-services/proto/mcp-scheduler/v1/scheduler.proto`)
   - Schedules and manages ephemeral pods for tenant jobs
   - Job lifecycle: create, monitor, cancel, logs

3. **MCP Server Service** (`go-services/proto/mcp-job/v1/mcp.proto`)
   - Reference backend for direct job execution

4. **Distributed Lock Service**
   - Provides distributed locking for concurrency control

5. **Throttle State Service**
   - Rate limiting and throttle management per tenant

6. **Health Service**
   - Health checking for platform services

Each service exposes strict, versioned protobuf APIs for backend and frontend consumption.

## Cluster Personas

The platform implements multiple personas for proper separation of concerns:

- **Cluster Administrator**
  - Full cluster access; manages platform deployment and lifecycle.
  - Provisions infra and global resources.

- **Tenant Administrator**
  - Full access within own namespace.
  - Deploys apps, manages RBAC, and updates policies inside the tenant scope.

- **Tenant User**
  - Standard role in the organization.
  - Can run jobs, deploy workloads, operate in own namespace, subject to quotas.

- **Tenant Viewer**
  - Read-only access to resources and logs in the tenant namespace.

## Key Features

### Multi-Tier Isolation
- **Namespace-level:** Standard (default)
- **Node Pool-level:** Dedicated pools for select tenants
- **Cluster-level:** Dedicated clusters for regulated/large customers

### Resource Management
- Automatic quotas (CPU, memory, PVCs, services, etc.) based on plan tier
- HPA and scaling hooks per tenant

### Network Isolation
- Strong network policy enforcement and egress control
- Multi-tenant pod communication strictly limited
- Kubernetes NetworkPolicy support

### AWS & Cloud Integration
- Secure IRSA for external cloud access
- Auto IAM/S3 isolation and resource mapping

### Ephemeral Job Execution
- Spin up pods for isolated tenant workloads
- Job state tracking and log retrieval
- Callback webhook support

### Distributed Coordination & Throttling
- Distributed locks prevent race conditions during provisioning or job start
- Tenant-aware rate limiting and circuit breaking

## Usage

### Prerequisites

- Kubernetes cluster (v1.24+ recommended)
- Go 1.22+ (or higher)
- [Buf](https://buf.build/) CLI for proto codegen
- AWS EKS (for IRSA features, optional)

### Building Services

```bash
cd go-services
./start.sh  # Generates protobufs and builds Go services
```

### Deploying Manifests

Deploy manifests with your desired variables using environment substitution (the system expects variables such as `${TENANT_NAME}`):

```bash
export TENANT_NAME=my-tenant
envsubst < manifests/namespace.yaml | kubectl apply -f -
```

### API Usage Examples

See `api/example-calls.js` and the generated OpenAPI docs for example:

- Creating and managing tenant accounts
- Submitting jobs for execution
- Monitoring job status and logs

## Service APIs

gRPC service definitions can be found under `go-services/proto/`. Main APIs:

- **AccountProvisioningService**: Organization/tenant lifecycle management
- **MCPJobService**: Multi-tenant job scheduling and lifecycle
- **DistributedLockService**: Distributed lock APIs
- **ThrottleStateService**: Rate limiting and quota checks
- **HealthService**: Probes for availability

All services are designed for secure deployment on Kubernetes with mTLS support. APIs are documented via OpenAPI (generated in `gen/openapi/`).

For more on project structure, microservice details, and API schemas, see the respective proto files and code documentation.