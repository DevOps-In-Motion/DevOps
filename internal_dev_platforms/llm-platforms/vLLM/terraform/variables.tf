# ============================================================================
# VARIABLES - Input Variables for Terraform Configuration
# ============================================================================

variable "aws_region" {
    description = "AWS region for resources"
    type        = string
    default     = "us-east-2"
}

variable "llm_host_ami" {
    description = "AMI ID for LLM host instance"
    type        = string
    default     = "ami-01860f9261027f15f"
}

variable "llm_host_instance_type" {
    description = "Instance type for LLM host"
    type        = string
    default     = "m7i-flex.large"
}

variable "bastion_ami" {
    description = "AMI ID for bastion host instance"
    type        = string
    default     = "ami-0f5fcdfbd140e4ab7"
}

variable "bastion_instance_type" {
    description = "Instance type for bastion host"
    type        = string
    default     = "t3.micro"
}

variable "key_pair_name" {
    description = "Name of the EC2 key pair"
    type        = string
    default     = "bastion-key"
}

variable "key_pair_public_key" {
    description = "Public key for EC2 key pair (replace REPLACEME in main.tf or set via terraform.tfvars)"
    type        = string
    default     = "REPLACEME"
    sensitive   = true
}

variable "availability_zone" {
    description = "Availability zone for instances"
    type        = string
    default     = "us-east-2a"
}

variable "vpc_cidr" {
    description = "CIDR block for VPC"
    type        = string
    default     = "10.0.0.0/16"
}

variable "private_subnet_cidr" {
    description = "CIDR block for private subnet"
    type        = string
    default     = "10.0.1.0/24"
}

variable "public_subnet_cidr" {
    description = "CIDR block for public subnet"
    type        = string
    default     = "10.0.2.0/24"
}

variable "llm_host_volume_size" {
    description = "Root volume size for LLM host (GB)"
    type        = number
    default     = 100
}

variable "bastion_volume_size" {
    description = "Root volume size for bastion host (GB)"
    type        = number
    default     = 100
}

variable "ssh_user" {
    description = "SSH user for instances"
    type        = string
    default     = "ubuntu"
}

variable "ssh_key_path" {
    description = "Path to SSH private key"
    type        = string
    default     = "~/.ssh/bastion-key.pem"
}

variable "tags" {
    description = "Common tags for all resources"
    type        = map(string)
    default = {
        Project = "llm-api"
        ManagedBy = "terraform"
    }
}

