#!/bin/bash

set -e

# Configuration
AWS_REGION=${1:-"us-east-1"}
CLUSTER_NAME=${2:-"my-eks-cluster"}
DOMAIN=${3:-"example.com"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Setting up prerequisites for Multi-Tenant Jenkins on EKS${NC}"
echo "Region: ${AWS_REGION}"
echo "Cluster: ${CLUSTER_NAME}"
echo "Domain: ${DOMAIN}"
echo ""

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl is not installed. Please install it first.${NC}"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}AWS CLI is not installed. Please install it first.${NC}"
    exit 1
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Helm is not installed. Please install it first.${NC}"
    exit 1
fi

echo -e "${GREEN}Step 1: Verifying AWS credentials...${NC}"
aws sts get-caller-identity --region "$AWS_REGION" > /dev/null
echo "  ✓ AWS credentials verified"

echo -e "${GREEN}Step 2: Connecting to EKS cluster...${NC}"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
echo "  ✓ Kubeconfig updated"

echo -e "${GREEN}Step 3: Installing AWS Load Balancer Controller...${NC}"

# Check if already installed
if kubectl get deployment -n kube-system aws-load-balancer-controller &> /dev/null; then
    echo "  ✓ AWS Load Balancer Controller already installed"
else
    # Create IAM OIDC provider if not exists
    echo "  - Creating IAM OIDC provider..."
    eksctl utils associate-iam-oidc-provider --region="$AWS_REGION" --cluster="$CLUSTER_NAME" --approve || true
    
    # Download IAM policy
    echo "  - Downloading IAM policy..."
    curl -o /tmp/iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json
    
    # Create IAM policy
    echo "  - Creating IAM policy..."
    aws iam create-policy \
        --policy-name AWSLoadBalancerControllerIAMPolicy \
        --policy-document file:///tmp/iam_policy.json \
        --region "$AWS_REGION" 2>/dev/null || echo "    Policy already exists"
    
    # Get AWS Account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Create service account
    echo "  - Creating service account..."
    eksctl create iamserviceaccount \
        --cluster="$CLUSTER_NAME" \
        --namespace=kube-system \
        --name=aws-load-balancer-controller \
        --role-name AmazonEKSLoadBalancerControllerRole \
        --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
        --approve \
        --region="$AWS_REGION" || echo "    Service account already exists"
    
    # Install AWS Load Balancer Controller using Helm
    echo "  - Installing controller via Helm..."
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update
    
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --set clusterName="$CLUSTER_NAME" \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller \
        --set region="$AWS_REGION" \
        --set vpcId=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.resourcesVpcConfig.vpcId" --output text)
    
    echo "  ✓ AWS Load Balancer Controller installed"
fi

echo -e "${GREEN}Step 4: Verifying Load Balancer Controller...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/aws-load-balancer-controller -n kube-system
echo "  ✓ Load Balancer Controller is ready"

echo -e "${GREEN}Step 5: Setting up StorageClass...${NC}"
# Check if gp3 storage class exists
if kubectl get storageclass gp3 &> /dev/null; then
    echo "  ✓ gp3 StorageClass already exists"
else
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
    echo "  ✓ gp3 StorageClass created"
fi

echo -e "${GREEN}Step 6: Requesting/Verifying SSL Certificate...${NC}"
# Check if certificate exists
CERT_ARN=$(aws acm list-certificates --region "$AWS_REGION" --query "CertificateSummaryList[?DomainName=='*.${DOMAIN}'].CertificateArn" --output text)

if [ -z "$CERT_ARN" ]; then
    echo "  - No wildcard certificate found for *.${DOMAIN}"
    echo "  - Requesting new certificate..."
    
    CERT_ARN=$(aws acm request-certificate \
        --domain-name "*.${DOMAIN}" \
        --subject-alternative-names "${DOMAIN}" \
        --validation-method DNS \
        --region "$AWS_REGION" \
        --query CertificateArn \
        --output text)
    
    echo "  ✓ Certificate requested: ${CERT_ARN}"
    echo ""
    echo -e "${YELLOW}  IMPORTANT: You need to validate this certificate in ACM!${NC}"
    echo "  1. Go to AWS Certificate Manager in the AWS Console"
    echo "  2. Find the certificate for *.${DOMAIN}"
    echo "  3. Add the DNS validation records to Route53"
    echo "  4. Wait for validation to complete"
    echo ""
    echo "  Or run this command to get validation records:"
    echo "  aws acm describe-certificate --certificate-arn ${CERT_ARN} --region ${AWS_REGION}"
else
    echo "  ✓ Certificate already exists: ${CERT_ARN}"
fi

echo -e "${GREEN}Step 7: Verifying Route53 Hosted Zone...${NC}"
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
    --dns-name "$DOMAIN" \
    --query "HostedZones[0].Id" \
    --output text \
    --region "$AWS_REGION" | sed 's|/hostedzone/||')

if [ -z "$HOSTED_ZONE_ID" ] || [ "$HOSTED_ZONE_ID" == "None" ]; then
    echo -e "${YELLOW}  Warning: No hosted zone found for ${DOMAIN}${NC}"
    echo "  You need to create a hosted zone in Route53 for ${DOMAIN}"
else
    echo "  ✓ Hosted Zone found: ${HOSTED_ZONE_ID}"
fi

# Create environment file
echo -e "${GREEN}Step 8: Creating environment configuration file...${NC}"
cat > .env <<EOF
# AWS Configuration
AWS_REGION=${AWS_REGION}
CLUSTER_NAME=${CLUSTER_NAME}
DOMAIN=${DOMAIN}
CERTIFICATE_ARN=${CERT_ARN}

# Usage:
# source .env
# ./create-tenant.sh <tenant-name>
EOF
echo "  ✓ Environment file created: .env"

echo ""
echo -e "${GREEN}==================== SETUP COMPLETE ====================${NC}"
echo ""
echo "Configuration saved to .env file"
echo ""
echo "Next steps:"
echo "1. Source the environment file: source .env"
echo "2. If you requested a new certificate, validate it in ACM"
echo "3. Create your first tenant: ./create-tenant.sh tenant1"
echo ""
echo "Certificate ARN: ${CERT_ARN}"
echo "Hosted Zone ID: ${HOSTED_ZONE_ID}"
echo ""
echo -e "${GREEN}========================================================${NC}"