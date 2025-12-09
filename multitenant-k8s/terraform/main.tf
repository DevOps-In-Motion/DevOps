module "aws" {
  source = "./aws"
  
  aws_region   = var.aws_region
  cluster_name = var.cluster_name
  environment  = var.environment
  db_username  = var.db_username
  db_password  = var.db_password
}