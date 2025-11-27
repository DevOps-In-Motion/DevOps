# Go Services

gRPC-based microservices for multi-tenant Kubernetes namespace provisioning and job management.

## Services

### Account Provisioning Service
**Port:** 8080  
**Purpose:** Automates tenant namespace creation and infrastructure provisioning

**Capabilities:**
- Creates and manages Kubernetes namespaces
- Provisions RBAC roles (admin, user, viewer)
- Configures network policies for tenant isolation
- Sets resource quotas based on plan tier
- Manages AWS IAM roles and S3 prefixes
- Supports multiple isolation levels (namespace, node pool, cluster)

**Operations:**
- `CreateAccount` - Provision new tenant namespace
- `GetAccount` - Retrieve tenant details
- `UpdateAccount` - Modify plan tier or isolation level
- `DeleteAccount` - Cleanup tenant resources
- `ListAccounts` - List all tenants

### MCP Job Service
**Port:** 8081  
**Purpose:** Manages ephemeral job execution for tenant workloads

**Capabilities:**
- Creates and manages Kubernetes Jobs in tenant namespaces
- Monitors job status and lifecycle
- Retrieves job logs
- Supports job cancellation
- Enforces namespace-scoped access control

**Operations:**
- `CreateJob` - Launch ephemeral job pod
- `GetJob` - Retrieve job status and results
- `ListJobs` - List jobs for an organization
- `CancelJob` - Terminate running job
- `GetJobLogs` - Stream job logs

## Architecture

- **Protocol:** gRPC with mTLS
- **Code Generation:** Protocol Buffers via Buf
- **Language:** Go 1.25.4
- **Communication:** Secure service-to-service with certificate-based authentication

## Project Structure

```
go-services/
├── account-provisioning/    # Account provisioning service implementation
├── mcp-job-service/          # MCP job service implementation
├── saas/v1/                  # Protocol buffer definitions
│   └── services.proto        # gRPC service definitions
├── buf.yaml                  # Buf project configuration
├── buf.gen.yaml              # Code generation settings
├── go.mod                    # Go module dependencies
└── start.sh                  # Build and code generation script
```

## Building

### Prerequisites
- Go 1.25.4+
- Buf CLI
- Protocol buffer compiler

### Generate Code
```bash
./start.sh
```

This generates:
- Go gRPC client/server code from `.proto` files
- gRPC-Gateway REST API stubs
- OpenAPI/Swagger documentation

### Build Services
```bash
go build ./account-provisioning
go build ./mcp-job-service
```

## Security

- **mTLS:** Both services require client certificates for authentication
- **RBAC:** Services use Kubernetes RBAC with namespace-scoped permissions
- **Network Isolation:** Tenant namespaces are isolated via network policies
- **Validation:** Services validate `organization_id` to prevent cross-tenant access

## Configuration

Services require:
- mTLS certificates at `/etc/certs/server.crt` and `/etc/certs/server.key`
- Kubernetes cluster access (via ServiceAccount or kubeconfig)
- AWS credentials (for IAM role and S3 management)

## Deployment

Services are designed to run as Kubernetes deployments with:
- ServiceAccounts bound to appropriate RBAC roles
- Network policies restricting communication
- Resource limits and quotas
- Horizontal Pod Autoscaling support

