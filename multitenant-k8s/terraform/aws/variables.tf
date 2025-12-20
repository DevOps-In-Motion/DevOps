
# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "mcp-cluster"
}

variable "environment" {
  description = "Environment Name"
  type        = string
  default     = "staging"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "dbadmin"
  sensitive   = true
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

/*
variable "EC2_KEY_PAIR_PUBLIC_KEY" {
  description = "The key pair for the EC2 instances"
  type        = string
  default = "value"
  validation {
    condition = length(var.EC2_KEY_PAIR_PUBLIC_KEY) > 10
    error_message = "The KEY PAIR must be more than 10 chars"
  }
}
*/