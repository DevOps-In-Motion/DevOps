"""Deploy a configurable Node web app on Amazon EKS.

Stack:
  - VPC + EKS cluster (pulumi-eks docs pattern)
  - ECR repository + image build/push (from ./app)
  - WebApp ComponentResource (Deployment + LoadBalancer Service)

Config:
  pulumi config set name <greeting>              # shown as "Hello <greeting>"
  pulumi config set aws:region us-west-2
  pulumi config set minClusterSize 1
  pulumi config set maxClusterSize 3
  pulumi config set desiredClusterSize 2
  pulumi config set eksNodeInstanceType t3.medium
  pulumi config set vpcNetworkCidr 10.0.0.0/16
"""

import pulumi
import pulumi_awsx as awsx
import pulumi_eks as eks
import pulumi_kubernetes as k8s
from pulumi import ResourceOptions

from webapp import WebApp, WebAppArgs

config = pulumi.Config()

# App config (defaults in Pulumi.yaml)
greeting = config.get("name") or "World"
replicas = config.get_int("replicas") or 2

# EKS / VPC config (defaults in Pulumi.yaml)
min_cluster_size = config.get_int("minClusterSize") or 3
max_cluster_size = config.get_int("maxClusterSize") or 6
desired_cluster_size = config.get_int("desiredClusterSize") or 3
eks_node_instance_type = config.get("eksNodeInstanceType") or "t3.medium"
vpc_network_cidr = config.get("vpcNetworkCidr") or "10.0.0.0/16"

# --- Container image (build Dockerfile in ./app, push to ECR) ---
repository = awsx.ecr.Repository(
    "webapp-repo",
    force_delete=True,
)

image = awsx.ecr.Image(
    "webapp-image",
    repository_url=repository.url,
    context="./app",
    platform="linux/amd64",
)

# --- VPC + EKS cluster (pulumi-eks docs pattern) ---
eks_vpc = awsx.ec2.Vpc(
    "eks-vpc",
    enable_dns_hostnames=True,
    cidr_block=vpc_network_cidr,
)

eks_cluster = eks.Cluster(
    "eks-cluster",
    vpc_id=eks_vpc.vpc_id,
    # API-only mode requires EKS access entries for the node role; pulumi-eks
    # self-managed nodes use aws-auth, so API_AND_CONFIG_MAP is required.
    authentication_mode=eks.AuthenticationMode.API_AND_CONFIG_MAP,
    public_subnet_ids=eks_vpc.public_subnet_ids,
    private_subnet_ids=eks_vpc.private_subnet_ids,
    instance_type=eks_node_instance_type,
    desired_capacity=desired_cluster_size,
    min_size=min_cluster_size,
    max_size=max_cluster_size,
    node_associate_public_ip_address=False,
    endpoint_private_access=False,
    endpoint_public_access=True,
)

k8s_provider = k8s.Provider(
    "k8s-provider",
    kubeconfig=eks_cluster.kubeconfig,
)

# --- App workload (ComponentResource) ---
app = WebApp(
    "greeting",
    WebAppArgs(
        image=image.image_uri,
        greeting=greeting,
        replicas=replicas,
    ),
    opts=ResourceOptions(provider=k8s_provider, depends_on=[eks_cluster]),
)

pulumi.export("greeting", greeting)
pulumi.export("kubeconfig", eks_cluster.kubeconfig)
pulumi.export("vpcId", eks_vpc.vpc_id)
pulumi.export("url", app.endpoint.apply(lambda host: f"http://{host}" if host else None))
