#!/bin/bash

set -e

# Configuration
TENANT_NAME=$1
DOMAIN=${2:-"example.com"}
AWS_REGION=${3:-"us-east-1"}
CLUSTER_NAME=${4:-"my-eks-cluster"}
CERTIFICATE_ARN=${5}

# Application Images (can be overridden via env vars)
FRONTEND_IMAGE=${FRONTEND_IMAGE:-"nginx:alpine"}
BACKEND_IMAGE=${BACKEND_IMAGE:-"node:18-alpine"}

# Database credentials (generate random if not provided)
DB_USER=${DB_USER:-"dbuser"}
DB_PASSWORD=${DB_PASSWORD:-$(openssl rand -base64 32 | tr -d /=+ | cut -c1-25)}
DB_NAME=${DB_NAME:-"${TENANT_NAME}_db"}
JWT_SECRET=${JWT_SECRET:-$(openssl rand -base64 64 | tr -d /=+ | cut -c1-64)}
API_KEY=${API_KEY:-$(openssl rand -hex 32)}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Validation
if [ -z "$TENANT_NAME" ]; then
    echo -e "${RED}Error: Tenant name is required${NC}"
    echo "Usage: $0 <tenant-name> [domain] [aws-region] [cluster-name] [certificate-arn]"
    echo "Example: $0 tenant1 example.com us-east-1 my-eks-cluster arn:aws:acm:us-east-1:123456789:certificate/xxx"
    exit 1
fi

if [ -z "$CERTIFICATE_ARN" ]; then
    echo -e "${YELLOW}Warning: No certificate ARN provided. You'll need to add it manually to ingress.yaml${NC}"
    CERTIFICATE_ARN="REPLACE_WITH_YOUR_CERTIFICATE_ARN"
fi

echo -e "${GREEN}Creating tenant: ${TENANT_NAME}${NC}"
echo "Domain: ${DOMAIN}"
echo "Region: ${AWS_REGION}"
echo "Cluster: ${CLUSTER_NAME}"
echo "Frontend Image: ${FRONTEND_IMAGE}"
echo "Backend Image: ${BACKEND_IMAGE}"
echo ""

# Create temporary directory for processed files
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# Function to process template files
process_template() {
    local input_file=$1
    local output_file=$2
    
    sed -e "s/\${TENANT_NAME}/${TENANT_NAME}/g" \
        -e "s/\${DOMAIN}/${DOMAIN}/g" \
        -e "s|\${CERTIFICATE_ARN}|${CERTIFICATE_ARN}|g" \
        -e "s|\${FRONTEND_IMAGE}|${FRONTEND_IMAGE}|g" \
        -e "s|\${BACKEND_IMAGE}|${BACKEND_IMAGE}|g" \
        -e "s/\${DB_USER}/${DB_USER}/g" \
        -e "s/\${DB_PASSWORD}/${DB_PASSWORD}/g" \
        -e "s/\${DB_NAME}/${DB_NAME}/g" \
        -e "s/\${JWT_SECRET}/${JWT_SECRET}/g" \
        -e "s/\${API_KEY}/${API_KEY}/g" \
        "$input_file" > "$output_file"
}

echo -e "${GREEN}Step 1: Processing Kubernetes manifests...${NC}"
# Process all YAML files
for file in k8s/*.yaml; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        process_template "$file" "$TMP_DIR/$filename"
        echo "  - Processed $filename"
    fi
done

echo -e "${GREEN}Step 2: Creating namespace and resources...${NC}"
kubectl apply -f "$TMP_DIR/namespace.yaml"
sleep 2

echo -e "${GREEN}Step 3: Creating RBAC...${NC}"
kubectl apply -f "$TMP_DIR/rbac.yaml"

echo -e "${GREEN}Step 4: Applying network policies...${NC}"
kubectl apply -f "$TMP_DIR/network-policy.yaml"

echo -e "${GREEN}Step 5: Creating StorageClass...${NC}"
kubectl apply -f "$TMP_DIR/storageclass.yaml"

echo -e "${GREEN}Step 6: Creating PersistentVolumeClaims...${NC}"
kubectl apply -f "$TMP_DIR/pvc.yaml"

echo -e "${GREEN}Step 7: Creating Secrets...${NC}"
kubectl apply -f "$TMP_DIR/secrets.yaml"

echo -e "${GREEN}Step 8: Creating ConfigMaps...${NC}"
kubectl apply -f "$TMP_DIR/configmap.yaml"

echo -e "${GREEN}Step 9: Deploying Database...${NC}"
kubectl apply -f "$TMP_DIR/database.yaml"

# Wait for database to be ready
echo -e "${YELLOW}Waiting for database to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=database -n "$TENANT_NAME" --timeout=300s || true

echo -e "${GREEN}Step 10: Deploying Backend API...${NC}"
kubectl apply -f "$TMP_DIR/backend.yaml"

# Wait for backend to be ready
echo -e "${YELLOW}Waiting for backend to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=backend -n "$TENANT_NAME" --timeout=300s || true

echo -e "${GREEN}Step 11: Deploying Frontend...${NC}"
kubectl apply -f "$TMP_DIR/frontend.yaml"

# Wait for frontend to be ready
echo -e "${YELLOW}Waiting for frontend to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=frontend -n "$TENANT_NAME" --timeout=300s || true

echo -e "${GREEN}Step 12: Creating Ingress...${NC}"
kubectl apply -f "$TMP_DIR/ingress.yaml"

# Wait for Load Balancer to be provisioned
echo -e "${YELLOW}Waiting for Load Balancer to be provisioned...${NC}"
sleep 15

LB_DNS=""
for i in {1..12}; do
    LB_DNS=$(kubectl get ingress ${TENANT_NAME}-ingress -n "$TENANT_NAME" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "$LB_DNS" ]; then
        break
    fi
    echo "  Attempt $i/12: Waiting for Load Balancer DNS..."
    sleep 10
done

if [ -z "$LB_DNS" ]; then
    echo -e "${YELLOW}Load Balancer DNS not yet available. Please check later with:${NC}"
    echo "kubectl get ingress ${TENANT_NAME}-ingress -n $TENANT_NAME"
else
    echo -e "${GREEN}Load Balancer DNS: ${LB_DNS}${NC}"
    
    # Create Route53 record
    echo -e "${GREEN}Step 13: Creating Route53 DNS record...${NC}"
    
    # Get Hosted Zone ID
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
        --dns-name "$DOMAIN" \
        --query "HostedZones[0].Id" \
        --output text \
        --region "$AWS_REGION" | sed 's|/hostedzone/||')
    
    if [ -z "$HOSTED_ZONE_ID" ] || [ "$HOSTED_ZONE_ID" == "None" ]; then
        echo -e "${YELLOW}Warning: Could not find hosted zone for $DOMAIN${NC}"
        echo "Please create the DNS record manually:"
        echo "  Record: ${TENANT_NAME}.${DOMAIN}"
        echo "  Type: CNAME"
        echo "  Value: ${LB_DNS}"
    else
        # Get Load Balancer Hosted Zone ID
        LB_HOSTED_ZONE_ID=$(aws elbv2 describe-load-balancers \
            --region "$AWS_REGION" \
            --query "LoadBalancers[?DNSName=='$LB_DNS'].CanonicalHostedZoneId" \
            --output text)
        
        # Create change batch JSON
        cat > "$TMP_DIR/change-batch.json" <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${TENANT_NAME}.${DOMAIN}",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${LB_HOSTED_ZONE_ID}",
          "DNSName": "${LB_DNS}",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF
        
        # Create the record
        aws route53 change-resource-record-sets \
            --hosted-zone-id "$HOSTED_ZONE_ID" \
            --change-batch file://"$TMP_DIR/change-batch.json" \
            --region "$AWS_REGION"
        
        echo -e "${GREEN}DNS record created: ${TENANT_NAME}.${DOMAIN}${NC}"
    fi
fi

# Save credentials to a secure file
CREDENTIALS_FILE="${TENANT_NAME}-cr