# Just-In-Time Access Setup Guide

This guide walks through the setup process for implementing Just-In-Time (JIT) access controls using Kubiya.

## Prerequisites

- A Kubernetes cluster (AKS, EKS, or GKE)
- Okta credentials (org URL, client ID, and private key)
- GitHub account with repository access
- AWS account with administrative access

## 1. Kubiya Runner Installation

### Steps:
1. Visit the [Kubiya Runner Installation Guide](https://docs.kubiya.ai/docs/kubiya-resources/local-runners/installation)
2. Navigate to the [Kubiya Runners Dashboard](https://app.kubiya.ai/runners)
3. Click "Add Local Runner"
4. Name your runner
5. Run the provided kubectl command in your terminal

### Notes:
- Kubiya Runner only supports Kubernetes environments (AKS, EKS, GKE)
- For private repository access, you'll need to create a Kubernetes secret with TOOLS_GH_TOKEN
  (Contact us for the secret creation script)

### GitHub Token Setup Script

Save the following script as `create_github_token_secret.sh`:

```bash
#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 [options] <GitHub token>"
    echo ""
    echo "Options:"
    echo "  --dry-run      Simulate the actions without applying any changes"
    echo "  --help         Display this help message"
    exit 1
}

# Parse arguments
dry_run_flag=""
token=""
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dry-run) dry_run_flag="--dry-run=client" ;;
        --help) usage ;;
        *) token=$1 ;;
    esac
    shift
done

# If no token was passed as an argument, prompt the user
if [ -z "$token" ]; then
    echo "Enter your GitHub token:"
    read -s token
fi

# Create or update the Kubernetes secret
kubectl delete secret github-token -n kubiya $dry_run_flag &>/dev/null
kubectl create secret generic github-token -n kubiya --from-literal=gh-token=$token $dry_run_flag

# Define the patch content
patch=$(cat <<EOF
spec:
  template:
    spec:
      containers:
        - name: tool-manager
          env:
            - name: TOOLS_GH_TOKEN
              valueFrom:
                secretKeyRef:
                  name: github-token
                  key: gh-token
        - name: kubiya-sdk-server
          env:
            - name: TOOLS_GH_TOKEN
              valueFrom:
                secretKeyRef:
                  name: github-token
                  key: gh-token
EOF
)

# Apply the patch to the deployment
kubectl patch deployment -n kubiya tool-manager --patch "$patch" $dry_run_flag

# Optionally restart the deployment if not in dry-run mode
if [ -z "$dry_run_flag" ]; then
    kubectl rollout restart deployment -n kubiya tool-manager
fi
```

Usage:
```bash
# To run normally with a GitHub token as an argument:
./create_github_token_secret.sh <your-github-token>

# To run in dry-run mode:
./create_github_token_secret.sh --dry-run <your-github-token>

# To display the help message:
./create_github_token_secret.sh --help
```

This script will create the necessary Kubernetes secret and configure the deployment to use it.

## 2. Enforcer Setup

### Prerequisites:
- Okta credentials
- GitHub repository for hosting OPA policy
- Access to spring.rego policy file

### Setup Options:
- [Setup Guide with SSH](https://docs.google.com/document/d/1KxVR6try2f3NmsqZ_mLaTjoFhezfmydjSArFvVCDiPI/edit?usp=sharing)
- [Setup Guide without SSH](https://docs.google.com/document/d/1TYkk5uA8UXSzEsO3Lw7kb74f5PkvaL7La0e3vNniAwc/edit?usp=sharing)
- [Community Tools Enforcer Documentation](https://github.com/kubiyabot/community-tools/blob/main/just_in_time_access/docs/Kubiya_Enforcer_Deployment.md)

### Steps:
1. Host the spring.rego file in a GitHub repository
2. Configure repository permissions for OPAL access
3. Use the repository URL as OPAL_POLICY_REPO_URL during setup
4. Follow the appropriate setup guide based on your SSH preference

## 3. AWS Integration Setup

### Prerequisites:
- AWS account with administrative access
- Ability to create or modify IAM roles

### Required Permissions

The role needs the following minimum permissions to function properly:

#### SSO Administration
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sso:ListInstances",
                "sso-admin:ListInstances",
                "sso-admin:ListPermissionSets",
                "sso-admin:DescribePermissionSet",
                "sso-admin:CreateAccountAssignment",
                "sso-admin:DeleteAccountAssignment"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "identitystore:ListUsers"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:ResourceTag/Environment": "${aws:PrincipalTag/Environment}"
                }
            }
        }
    ]
}
```

#### IAM Permissions
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:ListUsers",
                "iam:GetUser",
                "iam:ListUserTags"
            ],
            "Resource": "arn:aws:iam::${aws:AccountId}:user/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iam:GetAccountAlias",
                "iam:ListAccountAliases"
            ],
            "Resource": "*"
        }
    ]
}
```

#### S3 Permissions (if using S3 JIT access)
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetBucketPolicy",
                "s3:PutBucketPolicy",
                "s3:HeadBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${aws:PrincipalTag/AllowedBucket}",
                "arn:aws:s3:::${aws:PrincipalTag/AllowedBucket}/*"
            ],
            "Condition": {
                "StringEquals": {
                    "aws:ResourceTag/Environment": "${aws:PrincipalTag/Environment}"
                }
            }
        }
    ]
}
```

### Important Security Notes:

1. **SSO Permissions**:
   - Only the minimum required SSO admin actions are included
   - Identity store access is scoped to specific environments using tags

2. **IAM Permissions**:
   - User operations are scoped to the current account
   - Removed unnecessary policy creation/deletion permissions
   - Account alias operations are read-only

3. **S3 Permissions**:
   - Bucket operations are scoped to specific buckets using tags
   - Access is restricted by environment
   - Operations are limited to policy management and bucket verification

4. **Best Practices**:
   - Use AWS Organizations SCPs to further restrict access
   - Implement resource tagging strategy
   - Regularly audit access patterns
   - Consider using AWS CloudTrail for monitoring these operations

5. **Additional Security Measures**:
   - Consider implementing condition keys for time-based access
   - Use VPC endpoints to restrict API access
   - Implement AWS KMS encryption for sensitive data

### Setup Steps

#### Option 1: Create a New Role for Kubiya

1. In the AWS Console, navigate to IAM > Roles
2. Click "Create Role"
3. For "Trusted entity type" select "AWS Account"
4. Select "Another AWS account"
5. Enter Kubiya's Account ID: `564407622114`
6. Do not check "Require external ID" or "Require MFA"
7. Click Next
8. Add required permissions (including SSO admin access)
9. Name your role and add a description
10. Review and create the role

#### Option 2: Modify Existing Role

1. Navigate to the existing role in IAM
2. Go to "Trust relationships"
3. Click "Edit trust policy"
4. Add the following trust relationship:
   ```json
   {
     "AWS": "arn:aws:iam::564407622114:root"
   }
   ```
5. Click "Update Policy"

### Important Notes:
- The role must have all the permissions listed above to function properly
- For S3 JIT access, ensure the role has permissions to modify bucket policies
- The role should be scoped to only the required buckets and resources when possible
- Consider using AWS Organizations SCPs to further restrict access if needed
- Keep the role ARN handy for configuration in Kubiya

## 4. AWS JIT Tools Configuration

We'll help you fork the Community-Tools Repository and configure AWS JIT tools to match your requirements.

### Example Configurations

#### Account Access Configuration