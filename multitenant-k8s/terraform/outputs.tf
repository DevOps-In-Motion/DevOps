# outputs.tf (root level)

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.aws.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.aws.cluster_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.aws.rds_endpoint
  sensitive   = true
}

output "redis_primary_endpoint" {
  description = "Redis primary endpoint"
  value       = module.aws.redis_primary_endpoint
}

output "rabbitmq_endpoint" {
  description = "RabbitMQ endpoint"
  value       = module.aws.rabbitmq_endpoint
  sensitive   = true
}

output "kafka_bootstrap_brokers" {
  description = "Kafka bootstrap brokers"
  value       = module.aws.kafka_bootstrap_brokers
}

output "api_gateway_url" {
  description = "API Gateway URL"
  value       = module.aws.api_gateway_url
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.aws.alb_dns_name
}

output "nat_gateway_ips" {
  description = "NAT Gateway IPs"
  value       = module.aws.nat_gateway_ips
}