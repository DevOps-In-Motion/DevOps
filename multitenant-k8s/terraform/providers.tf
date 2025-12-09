terraform {
  required_version = ">=1.5.7"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 6.25.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1.1"
    }
  }

}


provider "aws" {
  region = "us-east-2"
  profile = "default"
}