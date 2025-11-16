# DevOps-In-Motion

Welcome to DevOps-In-Motion! This repository contains a collection of DevOps projects, infrastructure-as-code configurations, CI/CD pipelines, and automation tools focused on cloud-native technologies, Kubernetes, and modern DevOps practices.

## 📋 Table of Contents

- [Overview](#overview)
- [Projects](#projects)
  - [Buildkite & Octopus Deploy](#buildkite--octopus-deploy)
  - [High Availability GKE](#high-availability-gke)
  - [Multi-Tenant Jenkins on EKS](#multi-tenant-jenkins-on-eks)
  - [LLM API Infrastructure](#llm-api-infrastructure)
  - [Homelab](#homelab)
  - [Minikube Cheatsheet](#minikube-cheatsheet)
  - [SRE Practices](#sre-practices)
- [Technologies](#technologies)
- [Getting Started](#getting-started)
- [Contributing](#contributing)
- [Contact](#contact)

## 🎯 Overview

This repository serves as a comprehensive collection of DevOps projects and automation tools, covering:

- **CI/CD Pipelines**: Buildkite, Octopus Deploy, Jenkins, GitHub Actions
- **Container Orchestration**: Kubernetes (GKE, EKS), Helm, ArgoCD
- **Infrastructure as Code**: Terraform, Ansible
- **Monitoring & Observability**: Prometheus, Grafana, SLO/SLI dashboards
- **Multi-Tenancy**: Namespace isolation, network policies, RBAC
- **Cloud Platforms**: AWS, GCP
- **Automation**: Shell scripts, Python tools, configuration management

## 🚀 Projects

### Buildkite & Octopus Deploy

**Location**: `buildkite--octopus/`

A complete CI/CD pipeline solution combining Buildkite for build orchestration and Octopus Deploy for deployment automation.

**Features**:
- Terraform infrastructure for Buildkite agents
- Ansible playbooks for agent configuration
- Automated agent setup and management
- Integration with Octopus Deploy for deployments

**Key Components**:
- `infra/terraform/`: Infrastructure provisioning
- `infra/ansible/`: Configuration management
- `buildkite.sh`: Agent setup scripts

**Documentation**: See `buildkite--octopus/readme.md` for detailed setup instructions.

---

### High Availability GKE

**Location**: `high-availability/`

Production-ready Google Kubernetes Engine (GKE) configuration with comprehensive monitoring, autoscaling, and reliability engineering practices.

**Features**:
- **Autoscaling Configuration**: Horizontal Pod Autoscaler (HPA) and Cluster Autoscaler
- **Node Pool Management**: Optimized for 1M+ requests/day with 3-tier architecture
- **SLO/SLI Dashboards**: Comprehensive metrics for availability, performance, and reliability
- **Blue/Green & Canary Deployments**: Terraform configurations for zero-downtime deployments
- **Runbooks**: Incident response procedures, troubleshooting guides, and post-mortem templates
- **Monitoring**: Prometheus, Grafana integration

**Key Components**:
- `terraform/`: GKE cluster and node pool configurations
- `gke-configuration.sh`: Cluster setup automation
- `runbooks/`: Operational procedures and incident response

**Use Cases**:
- Production workloads requiring high availability
- Applications with variable traffic patterns
- Services needing automated scaling
- Teams implementing SRE practices

**Documentation**: See `high-availability/README.md` for detailed configuration and metrics.

---

### Multi-Tenant Jenkins on EKS

**Location**: `multi-tenant-moderncloud/`

Enterprise-grade multi-tenant Jenkins deployment on Amazon EKS with complete namespace isolation, network policies, and automated tenant provisioning.

**Features**:
- **Namespace Isolation**: Each tenant gets a dedicated Kubernetes namespace
- **Network Policies**: Strict network isolation preventing cross-tenant communication
- **Subdomain Routing**: Each tenant accessible via unique subdomain (tenant1.domain.com)
- **Automated Provisioning**: Single command to create fully configured tenant
- **Resource Management**: ResourceQuotas and LimitRanges per tenant
- **SSL/TLS**: Automatic HTTPS with ACM certificates
- **RBAC**: Least-privilege access control per tenant
- **Persistent Storage**: Dedicated EBS volumes per Jenkins instance

**Key Components**:
- `templates/`: Kubernetes manifests for tenant resources
- `bash-auto/`: Automation scripts for tenant lifecycle management
- `Jenkinsfile`: Sample CI/CD pipeline
- `cluster-configuration.sh`: EKS cluster setup

**Architecture**:
- AWS Application Load Balancer (ALB) for ingress
- Route53 for DNS management
- AWS Certificate Manager (ACM) for SSL/TLS
- Network policies for tenant isolation

**Documentation**: See `multi-tenant-moderncloud/README.md` for complete setup and usage guide.

---

### LLM API Infrastructure

**Location**: `LLM-API/ollama-aws/`

Secure infrastructure setup for running LLM APIs (Ollama) on AWS using free tier resources.

**Features**:
- **EC2 Infrastructure**: Bastion host and API server instances
- **API Gateway**: Secure API endpoint configuration
- **Security Groups**: Network isolation and access control
- **Self-Healing**: Automated service recovery scripts
- **Terraform**: Complete infrastructure as code

**Key Components**:
- `terraform/`: AWS infrastructure provisioning
- `scripts/`: Bootstrap and service management scripts
- `ci-pipelines/`: CI/CD pipeline configurations

**Use Cases**:
- Running LLM inference workloads
- Cost-effective API hosting
- Development and testing environments

**Documentation**: See `LLM-API/ollama-aws/README.md` for setup instructions.

---

### Homelab

**Location**: `homelab/`

Personal lab environment with various Kubernetes, Ansible, and automation projects for learning and experimentation.

**Key Sub-projects**:

#### Certificate Practice (`cert-practice/`)
- Kubernetes exam preparation materials
- Ansible playbooks and examples
- Linux networking and system administration scripts
- Configuration management examples

#### CI/CD Demos (`CICD/`)
- GitHub Actions workflows
- Jenkins pipelines
- Container build examples
- Sample applications (Go, Python)

#### Virtual Cluster Demos (`demo_vcluster/`, `demos/demo_vcluster/`)
- vCluster setup and management
- ArgoCD integration
- Cert-manager configuration
- Just-In-Time (JIT) access patterns

#### Monitoring & Observability (`grafana_render/`, `k8s/prometheus-stack/`)
- Prometheus and Grafana deployments
- Service monitoring configurations
- Alerting rules
- Load testing tools

#### JIT Access (`JIT/`)
- Just-In-Time access request workflows
- Approval automation
- Python tools for access management

#### Kubernetes Resources (`k8s/`)
- ArgoCD configurations
- Cassandra deployments
- Prometheus stack
- Exam preparation materials

**Features**:
- Comprehensive Ansible playbooks
- Kubernetes manifests and configurations
- Monitoring and alerting setups
- Automation scripts and cheatsheets

---

### Minikube Cheatsheet

**Location**: `minikube-cheatsheet/`

Local Kubernetes development environment with Minikube, including sample applications and deployment examples.

**Features**:
- Minikube installation scripts
- Sample applications (Flask, PostgreSQL, Nginx)
- Ingress configuration examples
- Interview preparation cheatsheets
- Docker build examples

**Key Components**:
- `apps/`: Sample Kubernetes applications
- `flask/`: Python Flask application example
- `install.sh`: Minikube setup automation
- `interview_cheatsheet.sh`: Kubernetes interview preparation

**Use Cases**:
- Local Kubernetes development
- Learning Kubernetes concepts
- Testing deployments before production
- Interview preparation

---

### SRE Practices

**Location**: `sre/`

Site Reliability Engineering documentation, practices, and guidelines.

**Contents**:
- SLO/SLI definitions and metrics
- Incident response procedures
- Reliability engineering best practices
- Monitoring and alerting strategies

---

## 🛠 Technologies

### Cloud Platforms
- **AWS**: EKS, EC2, API Gateway, Route53, ACM, ALB
- **GCP**: GKE, Cloud Build, Cloud Monitoring

### Container & Orchestration
- **Kubernetes**: GKE, EKS, Minikube, vCluster
- **Docker**: Container builds and deployments
- **Helm**: Package management
- **ArgoCD**: GitOps deployments

### CI/CD
- **Buildkite**: Build orchestration
- **Octopus Deploy**: Deployment automation
- **Jenkins**: Multi-tenant CI/CD
- **GitHub Actions**: Workflow automation

### Infrastructure as Code
- **Terraform**: Cloud infrastructure provisioning
- **Ansible**: Configuration management

### Monitoring & Observability
- **Prometheus**: Metrics collection
- **Grafana**: Visualization and dashboards
- **SLO/SLI**: Service level objectives and indicators

### Languages & Tools
- **Bash**: Automation scripts
- **Python**: Tooling and automation
- **YAML**: Kubernetes and Ansible configurations
- **HCL**: Terraform configurations

---

## 🚦 Getting Started

### Prerequisites

- **Kubernetes**: `kubectl` (v1.28+)
- **Cloud CLI**: `aws-cli` or `gcloud`
- **Terraform**: v1.0+
- **Ansible**: v2.9+
- **Helm**: v3.x
- **Docker**: For container builds

### Quick Start

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd DevOps
   ```

2. **Choose a project**:
   - Review the project-specific README files in each directory
   - Each project has its own setup instructions

3. **Set up environment variables**:
   - Copy `.env.example` files where available
   - Configure cloud credentials and settings

4. **Follow project-specific documentation**:
   - Each project directory contains detailed README files
   - Review prerequisites and setup steps

### Common Setup Steps

1. **AWS Setup** (for EKS projects):
   ```bash
   aws configure
   eksctl create cluster --name my-cluster --region us-east-1
   ```

2. **GCP Setup** (for GKE projects):
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

3. **Kubernetes Access**:
   ```bash
   kubectl get nodes
   ```

---

## 📚 Project Structure

```
DevOps/
├── buildkite--octopus/      # CI/CD with Buildkite & Octopus
├── buildkite--platform/     # Frontend platform
├── high-availability/       # GKE production configurations
├── homelab/                 # Personal lab environment
├── LLM-API/                 # Ollama on AWS
├── minikube-cheatsheet/     # Local K8s development
├── multi-tenant-moderncloud/ # Multi-tenant Jenkins on EKS
├── sre/                     # SRE practices
├── scratch/                 # Experimental work
└── README.md                # This file
```

---

## 🤝 Contributing

Contributions are welcome! This repository is focused on:

- **ML Ops projects**: Looking to collaborate on ML Ops initiatives
- **Automation**: Empowering the community with automation tools
- **Best Practices**: Sharing DevOps and SRE best practices

### How to Contribute

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

---

## 📫 Contact

- **Email**: 5thcinematic@gmail.com
- **Collaboration**: Looking to collaborate on ML Ops projects

---

## ⚡ Fun Fact

We want the community to empower themselves with automation! This repository is designed to provide practical, production-ready examples that teams can use to improve their DevOps practices.

---

## 📄 License

This repository contains various projects with different purposes. Please check individual project directories for specific licensing information.

---

## 🔗 Useful Links

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Terraform Documentation](https://www.terraform.io/docs)
- [Ansible Documentation](https://docs.ansible.com/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)

---

**Happy Building! 🚀**
