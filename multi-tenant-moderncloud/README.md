# Multi-Tenant Jenkins on Kubernetes (EKS)

This repository provides a complete solution for deploying multi-tenant Jenkins instances on Amazon EKS with namespace-based isolation and subdomain routing.

## 📋 Table of Contents

- [Architecture Overview](#architecture-overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Infrastructure Components](#infrastructure-components)
- [Network Isolation](#network-isolation)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)

## 🏗 Architecture Overview

```
                                    Internet
                                        |
                                        v
                                  AWS Route 53
                            (*.yourdomain.com DNS)
                                        |
                                        v
                      AWS Application Load Balancer (ALB)
                              (SSL/TLS Termination)
                                        |
                    +-------------------+-------------------+
                    |                                       |
              tenant1.domain.com                   tenant2.domain.com
                    |                                       |
                    v                                       v
            +---------------+                       +---------------+
            | Namespace:    |                       | Namespace:    |
            | tenant1       |                       | tenant2       |
            |               |                       |               |
            | - Jenkins Pod |                       | - Jenkins Pod |
            | - Jenkins SVC |                       | - Jenkins SVC |
            | - PVC (20GB)  |                       | - PVC (20GB)  |
            | - Ingress     |                       | - Ingress     |
            | - Network     |                       | - Network     |
            |   Policies    |                       |   Policies    |
            +---------------+                       +---------------+
                    |                                       |
                    +----------- EKS Cluster ---------------+
                           (Shared Infrastructure)
```

### Key Design Principles

1. **Namespace Isolation**: Each tenant gets a dedicated Kubernetes namespace
2. **Subdomain Routing**: Traffic is routed based on subdomain (tenant1.domain.com, tenant2.domain.com)
3. **Network Policies**: Strict network isolation prevents cross-tenant communication
4. **Resource Quotas**: Each tenant has CPU, memory, and storage limits
5. **RBAC**: Role-based access control limits tenant permissions to their namespace
6. **Shared Infrastructure**: Cost-effective single EKS cluster with multiple tenants

## ✨ Features

- **Automated Tenant Provisioning**: Single command to create fully configured tenant
- **Network Isolation**: NetworkPolicies prevent inter-tenant communication
- **Resource Management**: ResourceQuotas and LimitRanges per tenant
- **Subdomain Routing**: Each tenant accessible via unique subdomain
- **SSL/TLS**: Automatic HTTPS with ACM certificates
- **Persistent Storage**: Each Jenkins instance has dedicated EBS volume
- **RBAC**: Least-privilege access control per tenant
- **DNS Automation**: Automatic Route53 record creation
- **Kubernetes-native CI/CD**: Jenkins pipelines run as Kubernetes pods

## 📦 Prerequisites

### Required Tools

- `kubectl` (v1.28+)
- `aws-cli` (v2.x)
- `helm` (v3.x)
- `eksctl` (optional, for easier setup)

### AWS Requirements

1. **EKS Cluster**: Running Kubernetes cluster (v1.28+)
2. **CNI Plugin**: Network policy-compatible CNI (Calico, Cilium, etc.) - **Required for network isolation**
3. **Route53 Hosted Zone**: For your domain
4. **ACM Certificate**: Wildcard certificate (*.yourdomain.com)
5. **IAM Permissions**: To create load balancers, Route53 records, etc.
6. **VPC Configuration**: Proper subnet tags for ALB controller

### AWS Subnet Tags

Ensure your VPC subnets are tagged correctly:

```bash
# Public subnets (for ALB)
kubernetes.io/role/elb=1
kubernetes.io/cluster/<cluster-name>=shared

# Private subnets (for pods)
kubernetes.io/role/internal-elb=1
kubernetes.io/cluster/<cluster-name>=shared
```

## 🚀 Quick Start

### Step 1: Clone Repository

```bash
git clone <repository-url>
cd multi-tenant-jenkins
```

### Step 2: Setup Prerequisites

Run the setup script to install required components:

```bash
chmod +x scripts/*.sh
./scripts/setup-prerequisites.sh us-east-1 my-eks-cluster yourdomain.com
```

This script will:
- Install AWS Load Balancer Controller
- Create gp3 StorageClass
- Request/verify ACM certificate
- Verify Route53 hosted zone
- Create `.env` configuration file

### Step 3: Validate Certificate (if new)

If a new certificate was requested, validate it in AWS Certificate Manager:

```bash
# Get certificate validation records
aws acm describe-certificate \
  --certificate-arn <arn-from-setup> \
  --region us-east-1
```

Add the DNS validation records to Route53 and wait for validation.

### Step 4: Source Environment

```bash
source .env
```

### Step 5: Create Your First Tenant

```bash
./scripts/create-tenant.sh tenant1
```

This will:
1. Create namespace with resource quotas
2. Setup RBAC
3. Apply network policies
4. Deploy Jenkins
5. Create ingress with ALB
6. Setup Route53 DNS record
7. Display Jenkins admin password

### Step 6: Access Jenkins

Wait for DNS propagation (1-5 minutes), then access:

```
https://tenant1.yourdomain.com
```

Login with:
- Username: `admin`
- Password: (displayed in terminal)

## 🔧 Infrastructure Components

### Directory Structure

```
.
├── k8s/
│   ├── namespace.yaml              # Namespace, ResourceQuota, LimitRange
│   ├── network-policy.yaml         # Network isolation rules
│   ├── rbac.yaml                   # ServiceAccount, Role, RoleBinding
│   ├── jenkins-deployment.yaml     # Jenkins Deployment, Service, PVC
│   └── ingress.yaml                # ALB Ingress configuration
├── scripts/
│   ├── setup-prerequisites.sh      # One-time setup
│   ├── create-tenant.sh            # Create new tenant
│   ├── delete-tenant.sh            # Delete tenant
│   └── list-tenants.sh             # List all tenants
├── Jenkinsfile                     # Sample CI/CD pipeline
└── README.md                       # This file
```

### Kubernetes Resources Per Tenant

| Resource | Purpose | Quantity |
|----------|---------|----------|
| Namespace | Isolation boundary | 1 |
| ResourceQuota | Limit tenant resources | 1 |
| LimitRange | Default pod limits | 1 |
| ServiceAccount | Jenkins identity | 1 |
| Role | Permissions in namespace | 1 |
| RoleBinding | Link SA to Role | 1 |
| NetworkPolicy | Block cross-tenant traffic | 2 |
| PersistentVolumeClaim | Jenkins data storage | 1 (20GB) |
| Deployment | Jenkins master | 1 (1 replica) |
| Service | Jenkins endpoint | 1 |
| Ingress | External access | 1 |

### Resource Limits Per Tenant

```yaml
CPU Requests: 10 cores
CPU Limits: 20 cores
Memory Requests: 20 GB
Memory Limits: 40 GB
Persistent Volume Claims: 10
Pods: 50
Services: 10
```

## 🔒 Network Isolation

### CNI Requirements

**Important**: Network policies require a Container Network Interface (CNI) that supports the NetworkPolicy API. Common CNI plugins that support network policies include:

- **Calico** (recommended for EKS)
- **Cilium** 
- **Weave Net**
- **Romana**

EKS clusters using the default VPC CNI do **not** support network policies. To enable network policy support on EKS:

```bash
# Install Calico CNI (recommended)
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-operator.yaml
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-crs.yaml
```

**Note**: Installing a new CNI will require cluster downtime and may affect existing workloads. Test in a non-production environment first.

### Network Policy Rules

Each tenant has two NetworkPolicies:

#### 1. Cross-Namespace Isolation (`deny-cross-namespace`)

**Ingress Rules:**
- ✅ Allow traffic from same namespace
- ✅ Allow traffic from ingress controller
- ❌ Block traffic from other tenant namespaces

**Egress Rules:**
- ✅ Allow traffic to same namespace
- ✅ Allow DNS queries (port 53)
- ✅ Allow HTTPS/HTTP to internet (plugins, SCM)
- ❌ Block traffic to other tenant namespaces

#### 2. Jenkins Agent Communication (`allow-jenkins-agent-communication`)

- ✅ Allow Jenkins agents to connect to master on ports 50000 and 8080

### Testing Network Isolation

```bash
# From tenant1 namespace, try to access tenant2 service (should fail)
kubectl run -it --rm debug --image=busybox -n tenant1 -- \
  wget -O- http://jenkins.tenant2.svc.cluster.local:8080 --timeout=5

# Should timeout or connection refused
```

## 📖 Usage

### Create a New Tenant

```bash
./scripts/create-tenant.sh <tenant-name> [domain] [region] [cluster-name] [cert-arn]
```

**Example:**
```bash
./scripts/create-tenant.sh acme example.com us-east-1 my-cluster arn:aws:acm:...
```

Or with environment variables:
```bash
source .env
./scripts/create-tenant.sh acme
```

### List All Tenants

```bash
./scripts/list-tenants.sh
```

Output:
```
==================== JENKINS TENANTS ====================

TENANT               STATUS     PODS            JENKINS URL
-----------------------------------------------------------
tenant1              Running    1 running       https://tenant1.example.com
tenant2              Running    1 running       https://tenant2.example.com

Total tenants: 2
```

### Delete a Tenant

```bash
./scripts/delete-tenant.sh <tenant-name> [domain] [region]
```

**Example:**
```bash
./scripts/delete-tenant.sh tenant1
```

This will:
1. Delete Route53 DNS record
2. Delete namespace (cascades to all resources)
3. Clean up load balancer

### Access Jenkins Admin Password

```bash
kubectl exec -n <tenant-name> \
  $(kubectl get pods -n <tenant-name> -l app=jenkins -o jsonpath='{.items[0].metadata.name}') \
  -- cat /var/jenkins_home/secrets/initialAdminPassword
```

### View Tenant Resources

```bash
# All resources
kubectl get all -n tenant1

# Pods
kubectl get pods -n tenant1

# Services
kubectl get svc -n tenant1

# Ingress
kubectl get ingress -n tenant1

# Storage
kubectl get pvc -n tenant1
```

### View Jenkins Logs

```bash
kubectl logs -f deployment/jenkins -n tenant1
```

### Scale Jenkins (if needed)

```bash
# Note: Jenkins doesn't support horizontal scaling out of the box
# This is for reference only
kubectl scale deployment jenkins --replicas=1 -n tenant1
```

## 🔍 Troubleshooting

### Jenkins Pod Not Starting

```bash
# Check pod status
kubectl get pods -n tenant1

# Describe pod for events
kubectl describe pod <pod-name> -n tenant1

# Check logs
kubectl logs <pod-name> -n tenant1
```

Common issues:
- Insufficient resources (check ResourceQuota)
- PVC not binding (check StorageClass)
- Image pull failures (check ImagePullPolicy)

### Load Balancer Not Created

```bash
# Check ingress status
kubectl describe ingress jenkins-ingress -n tenant1

# Check ALB controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Verify subnet tags
aws ec2 describe-subnets --subnet-ids <subnet-id>
```

Required subnet tags:
- `kubernetes.io/role/elb=1` (public subnets)
- `kubernetes.io/cluster/<cluster-name>=shared`

### DNS Not Resolving

```bash
# Check Route53 record
aws route53 list-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --query "ResourceRecordSets[?Name=='tenant1.example.com.']"

# Test DNS resolution
nslookup tenant1.example.com

# Check ingress
kubectl get ingress jenkins-ingress -n tenant1 -o yaml
```

### Certificate Issues

```bash
# Check certificate status
aws acm describe-certificate --certificate-arn <arn>

# Verify certificate is validated
aws acm list-certificates --certificate-statuses ISSUED
```

### Network Policy Issues

```bash
# Check if network policies are applied
kubectl get networkpolicies -n tenant1

# Describe network policy
kubectl describe networkpolicy deny-cross-namespace -n tenant1

# Test connectivity
kubectl run -it --rm debug --image=busybox -n tenant1 -- sh
```

### CNI Not Supporting Network Policies

If network policies are not working:

```bash
# Check current CNI
kubectl get pods -n kube-system | grep -E "(calico|cilium|weave|romana)"

# If using default VPC CNI, network policies won't work
kubectl get pods -n kube-system | grep aws-node

# Install Calico CNI (requires cluster downtime)
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-operator.yaml
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-crs.yaml

# Verify Calico is running
kubectl get pods -n calico-system
```

### Resource Quota Exceeded

```bash
# Check quota usage
kubectl describe resourcequota -n tenant1

# Increase quota (edit namespace.yaml and reapply)
kubectl apply -f k8s/namespace.yaml
```

## 🔐 Security Considerations

### 1. Network Isolation

- ✅ NetworkPolicies block cross-tenant communication
- ✅ Each tenant can only access their own resources
- ✅ Ingress controller is the only external entry point

### 2. RBAC

- ✅ Each tenant has a dedicated ServiceAccount
- ✅ Role grants permissions only within namespace
- ✅ No ClusterRole or ClusterRoleBinding used

### 3. Resource Limits

- ✅ ResourceQuota prevents resource exhaustion
- ✅ LimitRange sets default limits for pods
- ✅ Prevents noisy neighbor problems

### 4. Data Isolation

- ✅ Each tenant has dedicated PersistentVolume
- ✅ No shared volumes between tenants
- ✅ EBS volumes encrypted at rest

### 5. SSL/TLS

- ✅ All traffic encrypted with ACM certificates
- ✅ HTTP automatically redirects to HTTPS
- ✅ TLS 1.2+ enforced

### Best Practices

1. **Regular Updates**: Keep Jenkins and plugins updated
2. **Backup Strategy**: Implement backup for PersistentVolumes
3. **Monitoring**: Setup CloudWatch or Prometheus monitoring
4. **Audit Logging**: Enable EKS audit logs
5. **Credential Management**: Use AWS Secrets Manager or Kubernetes Secrets
6. **Pod Security**: Implement Pod Security Standards
7. **Regular Reviews**: Audit RBAC and NetworkPolicies regularly

## 📝 Jenkinsfile Example

The included `Jenkinsfile` demonstrates:

- **Kubernetes Pod Agent**: Pipelines run in ephemeral pods
- **Multi-container Pods**: kubectl, docker, aws-cli containers
- **Namespace-scoped Deployments**: Deploys only to tenant's namespace
- **Docker Build & Push**: Builds and pushes container images
- **Kubernetes Deployment**: Deploys applications to same namespace

### Using the Jenkinsfile

1. Create a new Pipeline job in Jenkins
2. Point to your SCM repository
3. Jenkins will automatically use the Jenkinsfile
4. The pipeline runs in the tenant's namespace

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details

## 🙋 Support

For issues and questions:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review AWS Load Balancer Controller logs
3. Check Jenkins logs
4. Open an issue in the repository

## 🔗 Useful Links

- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Jenkins on Kubernetes](https://www.jenkins.io/doc/book/installing/kubernetes/)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Route53 Documentation](https://docs.aws.amazon.com/route53/)
- [Multi-tenant K8S](https://kubernetes.io/docs/concepts/security/multi-tenancy/)
- [AWS CLI](aws.amazon.com)

---

**Happy Building! 🚀**