# Configurable web app on Amazon EKS (Pulumi + Python)

Deploys a Node.js Express app to a Kubernetes cluster on **AWS EKS**. The greeting on the page comes from **Pulumi config** → pod env `NAME` → `server.js`.

## What's included

| Piece | Where |
| --- | --- |
| Dockerfile + Node app | `app/` |
| Pulumi program (Python) | `__main__.py` |
| `WebApp` **ComponentResource** (Deployment + Service) | `webapp.py` |
| EKS cluster | `__main__.py` via `pulumi-eks` |
| Image build/push to ECR | `awsx.ecr.Image` |

## Prerequisites

**Tools**

- [Pulumi CLI](https://www.pulumi.com/docs/install/)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) v2 (`aws --version`)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) (`kubectl version --client`)
- Python 3.10+
- Docker running (for image builds)

**AWS authentication**

Pulumi and `kubectl` both call AWS APIs. You must be authenticated **before** `pulumi up` or configuring the cluster context.

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

**IAM permissions**

The deploying principal needs permission to create and manage the resources this stack provisions. For a demo, attaching **AdministratorAccess** (or an equivalent admin role) is simplest. Minimum service coverage:

| Service | What this stack uses it for |
| --- | --- |
| **EKS** | Cluster, node groups, addons, access config, `DescribeCluster` |
| **EC2** | VPC, subnets, routes, IGW, NAT, security groups, launch templates, instances |
| **IAM** | Cluster/node/instance roles, policies, instance profiles, `PassRole` |
| **ECR** | Repository, image push/pull, `GetAuthorizationToken` |
| **Elastic Load Balancing** | Classic/ELB for the Kubernetes `LoadBalancer` Service |
| **Auto Scaling** | Worker node ASG |
| **CloudWatch Logs** | EKS control plane logging (if enabled) |
| **STS** | `GetCallerIdentity` (verify credentials) |

Representative actions (not exhaustive):

- `eks:*` (or create/describe/update/delete cluster, nodegroup, addon, access entry)
- `ec2:*` on VPC networking, security groups, instances, launch templates
- `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PassRole`, `iam:CreateInstanceProfile`, `iam:GetRole`
- `ecr:*` (or create repository, batch check layer availability, put image, get authorization token)
- `elasticloadbalancing:*` (create/describe/register targets for the Service LB)
- `autoscaling:*` (create/update ASG for worker nodes)
- `logs:CreateLogGroup`, `logs:DescribeLogGroups` (if cluster logging is on)
- `sts:GetCallerIdentity`

Without these, `pulumi up` fails (often at EKS, ECR, or the node ASG). `kubectl` also needs `eks:DescribeCluster` and permission to call `aws eks get-token` for the cluster.

> EKS incurs real AWS cost. Tear down with `pulumi destroy` when finished.

## Setup

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

## Deploy

```bash
pulumi up
```

When the LoadBalancer is ready:

```bash
pulumi stack output url
curl "$(pulumi stack output url)"
# Hello Pulumi
```

Change the greeting without rebuilding the image logic—just config + update:

```bash
pulumi config set name Alice
pulumi up
curl "$(pulumi stack output url)"
# Hello Alice
```

## Configure kubectl

After `pulumi up`, use the stack's kubeconfig (recommended — matches what Pulumi deployed):

```bash
cd pulumi
source ../_keys/load-cloud.sh   # AWS creds for aws eks get-token

pulumi stack output kubeconfig --show-secrets > kubeconfig.yaml
export KUBECONFIG="$PWD/kubeconfig.yaml"
```

Check the cluster and app:

```bash
kubectl get nodes
kubectl get pods
kubectl get svc

curl "$(pulumi stack output url)"
# Hello Pulumi
```

`kubeconfig.yaml` contains cluster credentials — do not commit it (listed in `.gitignore`).

### LoadBalancer DNS (AWS CLI)

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

## Local app smoke test (no cloud)

```bash
cd app
npm install
export $(grep -v '^#' local.env | xargs)   # NAME=Pulumi
npm start
# curl http://localhost:8080  → Hello Pulumi
```

## Tear down

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
