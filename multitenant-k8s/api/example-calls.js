// 1. On signup
POST http://account-service:8080/api/accounts
{
  "organization_id": "customer123",
  "organization_type": "namespace",
  "plan_tier": "pro"
}

// 2. On job request
POST http://mcp-job-service:8081/api/mcp/jobs
{
  "organization_id": "customer123",
  "job_type": "code_analysis",
  "prompt": "Analyze this code",
  "callback_url": "https://your-backend/webhook"
}