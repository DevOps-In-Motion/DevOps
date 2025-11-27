**How IRSA Works:**

1. MCP Pod has ServiceAccount: mcp-sa
2. ServiceAccount has annotation: eks.amazonaws.com/role-arn
3. EKS injects AWS credentials into pod via projected volume
4. Pod uses credentials to call AWS APIs (S3, etc.)
5. AWS validates: Is this pod allowed to assume this role?