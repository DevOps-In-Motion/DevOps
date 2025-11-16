#!/bin/bash

set -e

# Configuration
TENANT_NAME=$1
DOMAIN=${2:-"example.com"}
AWS_REGION=${3:-"us-east-1"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validation
if [ -z "$TENANT_NAME" ]; then
    echo -e "${RED}Error: Tenant name is required${NC}"
    echo "Usage: $0 <tenant-name> [domain] [aws-region]"
    echo "Example: $0 tenant1 example.com us-east-1"
    exit 1
fi

echo -e "${YELLOW}WARNING: This will delete the entire tenant and all its resources!${NC}"
echo "Tenant: ${TENANT_NAME}"
echo "Domain: ${TENANT_NAME}.${DOMAIN}"
echo "This includes:"
echo "  - All applications (frontend, backend, database)"
echo "  - All persistent data (databases, volumes)"
echo "  - All secrets and configuration"
echo "  - DNS records"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo -e "${GREEN}Deleting tenant: ${TENANT_NAME}${NC}"

# Delete Route53 record
echo -e "${GREEN}Step 1: Deleting Route53 DNS record...${NC}"
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
    --dns-name "$DOMAIN" \
    --query "HostedZones[0].Id" \
    --output text \
    --region "$AWS_REGION" | sed 's|