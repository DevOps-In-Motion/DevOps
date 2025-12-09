variable "AWS_ACCESS_KEY_ID" {
  description = "The aws_access_key"
  type        = string
  default = "value"
  validation {
    condition = length(var.AWS_ACCESS_KEY_ID) > 10
    error_message = "The file must be more than 10 chars"
  }
}

variable "AWS_SECRET_ACCESS_KEY" {
  description = "The id aws_secret_key"
  type        = string
  default = "value"
  validation {
    condition = length(var.AWS_SECRET_ACCESS_KEY) > 10
    error_message = "The file must be more than 10 chars"
  }
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "job-scheduler-cluster"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
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