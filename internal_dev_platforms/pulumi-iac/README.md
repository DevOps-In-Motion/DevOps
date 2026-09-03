# Configurable Web App on Amazon EKS (Pulumi + Python)

A fully infrastructure-as-code project that provisions an **AWS EKS** cluster and deploys a containerized Node.js Express application — all managed by **Pulumi** in Python. The app serves a greeting page whose message is driven entirely by `pulumi config`, demonstrating how a single config change flows through to a live web page without rebuilding the container image.

## Key Design Decisions

- **`WebApp` ComponentResource** (`webapp.py`) — encapsulates the Kubernetes `Deployment` and `Service` into a single reusable component, making it easy to stamp out additional apps on the same cluster.
- **Config-driven behavior** — the greeting value is set via `pulumi config set name <value>`, injected as an environment variable into the pod, and read by `server.js` at runtime. Changing it and running `pulumi up` updates the page immediately.
- **Fully containerized** — a `Dockerfile` in `app/` builds the image; Pulumi automatically builds and pushes it to an **ECR** repository via `awsx.ecr.Image`.

## Project Structure

| Component | Location | Purpose |
| --- | --- | --- |
| Dockerfile + Node.js app | `app/` | Serves `Hello ${NAME}` on port 8080 |
| Pulumi program | `__main__.py` | Provisions EKS cluster, ECR image, and the `WebApp` component |
| `WebApp` ComponentResource | `webapp.py` | Reusable component wrapping a Deployment + LoadBalancer Service |

## Prerequisites

**Tools**

- [Pulumi CLI](https://www.pulumi.com/docs/install/)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) v2 (`aws --version`)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) (`kubectl version --client`)
- Python 3.10+
- Docker running (for image builds)

**AWS Authentication**

Pulumi and `kubectl` both call AWS APIs. You must be authenticated **before** running `pulumi up` or configuring the cluster context.

Either:

1. **Credential file + loader (this repo)** — create `_keys/cloud` at the repo root (not committed):

   ```
   AWS_ACCESS_KEY_ID=your_access_key
   AWS_SECRET_ACCESS_KEY=your_secret_key
   ```

   Then in every shell session:

   ```bash
   source _keys/load-cloud.sh
   aws sts get-caller-identity   # should succeed
   ```

2. **Another method** — `aws configure`, `aws sso login`, or exported `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` with the same IAM permissions below.

**IAM Permissions**

The deploying principal needs permission to create and manage the resources this stack provisions. For a quick start, attaching **AdministratorAccess** (or an equivalent admin role) works. Minimum service coverage:

| Service | Used For |
| --- | --- |
| **EKS** | Cluster, node groups, addons, access config, `DescribeCluster` |
| **EC2** | VPC, subnets, routes, IGW, NAT, security groups, launch templates, instances |
| **IAM** | Cluster/node/instance roles, policies, instance profiles, `PassRole` |
| **ECR** | Repository, image push/pull, `GetAuthorizationToken` |
| **Elastic Load Balancing** | Classic/ELB for the Kubernetes `LoadBalancer` Service |
| **Auto Scaling** | Worker node ASG |
| **CloudWatch Logs** | EKS control plane logging (if enabled) |
| **STS** | `GetCallerIdentity` (verify credentials) |

<details>
<summary>Representative IAM actions (not exhaustive)</summary>

- `eks:*` (or create/describe/update/delete cluster, nodegroup, addon, access entry)
- `ec2:*` on VPC networking, security groups, instances, launch templates
- `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PassRole`, `iam:CreateInstanceProfile`, `iam:GetRole`
- `ecr:*` (or create repository, batch check layer availability, put image, get authorization token)
- `elasticloadbalancing:*` (create/describe/register targets for the Service LB)
- `autoscaling:*` (create/update ASG for worker nodes)
- `logs:CreateLogGroup`, `logs:DescribeLogGroups` (if cluster logging is on)
- `sts:GetCallerIdentity`

Without these, `pulumi up` fails (often at EKS, ECR, or the node ASG). `kubectl` also needs `eks:DescribeCluster` and permission to call `aws eks get-token` for the cluster.
</details>

> **Cost warning:** EKS incurs real AWS charges. Tear down with `pulumi destroy` when finished.

## Quick Start

### 1. Setup

```bash
cd pulumi
source ../_keys/load-cloud.sh   # or use aws configure / SSO

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

pulumi stack select dev   # or: pulumi stack init dev
pulumi config set name Pulumi          # overrides default "World"
# other keys have defaults in Pulumi.yaml; override as needed:
# pulumi config set desiredClusterSize 2
# pulumi config set aws:region us-east-1
```

### 2. Deploy

```bash
pulumi up
```

Once the LoadBalancer is ready, open the URL in a browser:

```bash
pulumi stack output url
curl "$(pulumi stack output url)"
# Hello Pulumi
```

### 3. Change the Greeting (Config-Only Update)

No image rebuild needed — just update the config and redeploy:

```bash
pulumi config set name Alice
pulumi up
curl "$(pulumi stack output url)"
# Hello Alice
```

Reload the page in a browser to see the updated greeting.

## Working with kubectl

After `pulumi up`, export the stack's kubeconfig (recommended — matches what Pulumi deployed):

```bash
cd pulumi
source ../_keys/load-cloud.sh   # AWS creds for aws eks get-token

pulumi stack output kubeconfig --show-secrets > kubeconfig.yaml
export KUBECONFIG="$PWD/kubeconfig.yaml"
```

Inspect the cluster and app:

```bash
kubectl get nodes
kubectl get pods
kubectl get svc

curl "$(pulumi stack output url)"
# Hello Pulumi
```

`kubeconfig.yaml` contains cluster credentials — do not commit it (listed in `.gitignore`).

### LoadBalancer DNS (alternative lookups)

Pulumi output is easiest: `pulumi stack output url`

Or via Kubernetes:

```bash
kubectl get svc greeting -o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}{"\n"}'
```

Classic ELB (this stack's Service type):

```bash
aws elb describe-load-balancers --region us-west-2 \
  --query 'LoadBalancerDescriptions[*].[LoadBalancerName,DNSName]' \
  --output table
```

## Local Smoke Test (No Cloud Required)

Run the app locally to verify behavior before deploying:

```bash
cd app
npm install
export $(grep -v '^#' local.env | xargs)   # NAME=Pulumi
npm start
# curl http://localhost:8080  → Hello Pulumi
```

## Tear Down

```bash
pulumi destroy
```

## Architecture

```
pulumi config (name)
        │
        ▼
WebApp ComponentResource
  ├─ Deployment  (env NAME=<name>)
  └─ Service     (LoadBalancer :80 → :8080)
        │
        ▼
   app/server.js  →  "Hello ${NAME}"
```
