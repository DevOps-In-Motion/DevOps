# Configure terraform cloud
terraform {
  cloud {
    organization = "Energy_Stars"

    workspaces {
      name = "TFMultiCloud"
    }
  }
}

module "aws" {
  source = "./modules/aws_instance"
  AWS_ACCESS_KEY_ID  = var.AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY  = var.AWS_SECRET_ACCESS_KEY 
}

module "google" {
  source = "./modules/gcp_instance"
  GOOGLE_CREDENTIALS = var.GOOGLE_CREDENTIALS
}


provider "google" {
  project = "<YOUR_PROJECT_ID>"
  region  = "<YOUR_REGION>"
}