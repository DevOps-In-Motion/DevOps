# Configure terraform cloud
terraform {
  cloud {
    organization = "DevOpsInMotion"

    workspaces {
      name = "Buildkite--OctopusDeploy"
    }
  }
}

module "aws" {
  source = "./modules/"
  AWS_ACCESS_KEY_ID  = var.AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY  = var.AWS_SECRET_ACCESS_KEY 
}
