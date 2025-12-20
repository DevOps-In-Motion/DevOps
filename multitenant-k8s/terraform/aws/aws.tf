provider "aws" {
  region = "us-east-1" # Modify to your desired region

}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet" "subnet_1" {
  vpc_id = data.aws_vpc.default.id
  cidr_block = "172.31.64.0/20"
}

# VPC Configuration - Private EKS with NAT Gateway for outbound traffic
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  database_subnets = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]

  # NAT Gateway configuration - all private subnet traffic goes through NAT
  enable_nat_gateway   = true
  single_nat_gateway   = false  # One NAT per AZ for high availability
  one_nat_gateway_per_az = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  create_database_subnet_group = true

  # Tags for public subnets - used only for NAT gateways and load balancers
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
    "Tier" = "Public"
  }

  # Tags for private subnets - EKS nodes will be launched here
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery" = var.cluster_name
    "Tier" = "Private"
  }

  # Tags for database subnets
  database_subnet_tags = {
    "Tier" = "Database"
  }

  tags = {
    Environment = var.environment
    Terraform   = "true"
  }
}

# Define a security group for your instances
resource "aws_security_group" "ec2_sg" {
  name_prefix = "${var.cluster_name}-sg"

  # Define your security group rules here
  # Example rule for SSH access:
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
   }
}

# EKS Cluster - Fully private with NAT gateway for outbound traffic
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"
  kubernetes_version = "1.31"
  name = "${var.cluster_name}-${var.environment}"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets  # Nodes will be provisioned here
  control_plane_subnet_ids = module.vpc.private_subnets  # EKS control plane ENIs in private subnets

  # Private cluster configuration - API endpoint not publicly accessible
  endpoint_public_access  = false
  endpoint_private_access = true

  # OIDC Provider for IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  # Enable cluster creator admin permissions
  enable_cluster_creator_admin_permissions = true

  # Cluster access entry for additional users/roles (optional)
  # authentication_mode = "API_AND_CONFIG_MAP"  # Default value

  # EKS Managed Node Groups
  eks_managed_node_groups = {
    general = {
      name = "general-node-group"
      
      min_size     = 2
      max_size     = 10
      desired_size = 3

      instance_types = ["t3.large"]
      capacity_type  = "ON_DEMAND"

      # Node group will use private subnets from subnet_ids
      subnet_ids = module.vpc.private_subnets

      labels = {
        role = "general"
      }

      tags = {
        NodeGroup = "general"
      }
    }

    workers = {
      name = "worker-node-group"
      
      min_size     = 1
      max_size     = 20
      desired_size = 2

      instance_types = ["t3.xlarge"]
      capacity_type  = "SPOT"

      # Node group will use private subnets from subnet_ids
      subnet_ids = module.vpc.private_subnets

      labels = {
        role        = "worker"
        workload    = "job-execution"
      }

      taints = {
        dedicated = {
          key    = "workload"
          value  = "job-execution"
          effect = "NO_SCHEDULE"
        }
      }

      tags = {
        NodeGroup = "workers"
      }
    }
  }

  # Node security group additional rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    # Allow nodes to communicate with ALB
    ingress_alb_all = {
      description              = "ALB to node all ports"
      protocol                 = "-1"
      from_port                = 0
      to_port                  = 0
      type                     = "ingress"
      source_security_group_id = aws_security_group.alb.id
    }
    # Egress through NAT gateway
    egress_all = {
      description = "Node all egress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = {
    Environment = var.environment
  }
}

# Application Load Balancer Security Group (in public subnets)
resource "aws_security_group" "alb" {
  name        = "${var.cluster_name}-alb-sg"
  description = "Security group for public ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-alb-sg"
  }
}

# Application Load Balancer (Public facing, routes to private EKS)
resource "aws_lb" "main" {
  name               = "${var.cluster_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false
  enable_http2              = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name        = "${var.cluster_name}-alb"
    Environment = var.environment
  }
}

# Target group for ALB (will be used by ingress controller)
resource "aws_lb_target_group" "main" {
  name        = "${var.cluster_name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  deregistration_delay = 30

  tags = {
    Name = "${var.cluster_name}-tg"
  }
}

# ALB Listener - HTTP (redirect to HTTPS in production)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ALB Listener - HTTPS (requires certificate)
# Uncomment and configure after obtaining ACM certificate
# resource "aws_lb_listener" "https" {
#   load_balancer_arn = aws_lb.main.arn
#   port              = "443"
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
#   certificate_arn   = aws_acm_certificate.main.arn
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.main.arn
#   }
# }

# RDS PostgreSQL Database
resource "aws_db_subnet_group" "postgres" {
  name       = "${var.cluster_name}-postgres-subnet-group"
  subnet_ids = module.vpc.database_subnets

  tags = {
    Name = "${var.cluster_name}-postgres-subnet-group"
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.cluster_name}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "PostgreSQL from EKS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-rds-sg"
  }
}

resource "aws_db_instance" "postgres" {
  identifier     = "${var.cluster_name}-postgres"
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.large"

  allocated_storage     = 100
  max_allocated_storage = 500
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "jobscheduler"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "mon:04:00-mon:05:00"

  multi_az               = true
  publicly_accessible    = false
  skip_final_snapshot    = false
  final_snapshot_identifier = "${var.cluster_name}-postgres-final-snapshot"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  performance_insights_enabled = true
  performance_insights_retention_period = 7

  tags = {
    Name        = "${var.cluster_name}-postgres"
    Environment = var.environment
  }
}

# ElastiCache Redis for Distributed Locking
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.cluster_name}-redis-subnet-group"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "redis" {
  name        = "${var.cluster_name}-redis-sg"
  description = "Security group for Redis"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Redis from EKS"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-redis-sg"
  }
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "${var.cluster_name}-redis"
  automatic_failover_enabled  = true
  preferred_cache_cluster_azs = ["us-west-2a", "us-west-2b"]
  description                 = "example description"
  node_type                   = "cache.m4.large"
  num_cache_clusters          = 2
  parameter_group_name        = "default.redis3.2"
  port                        = 6379

  multi_az_enabled          = true
  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  snapshot_retention_limit = 5
  snapshot_window         = "03:00-05:00"
  tags = {
    Name        = "${var.cluster_name}-redis"
    Environment = var.environment
  }
}

# Amazon MQ (RabbitMQ)
resource "aws_security_group" "rabbitmq" {
  name        = "${var.cluster_name}-rabbitmq-sg"
  description = "Security group for RabbitMQ"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "AMQP from EKS"
    from_port       = 5671
    to_port         = 5671
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  ingress {
    description     = "RabbitMQ Management from EKS"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-rabbitmq-sg"
  }
}

resource "aws_mq_broker" "rabbitmq" {
  broker_name = "${var.cluster_name}-rabbitmq"
  engine_type = "RabbitMQ"
  engine_version = "3.11.20"
  
  host_instance_type = "mq.m5.large"
  deployment_mode    = "CLUSTER_MULTI_AZ"

  user {
    username = "admin"
    password = var.db_password # Use a separate variable in production
  }

  subnet_ids         = module.vpc.private_subnets
  security_groups    = [aws_security_group.rabbitmq.id]
  publicly_accessible = false

  logs {
    general = true
  }

  tags = {
    Name        = "${var.cluster_name}-rabbitmq"
    Environment = var.environment
  }
}

# MSK (Managed Kafka) for Event Streaming
resource "aws_security_group" "msk" {
  name        = "${var.cluster_name}-msk-sg"
  description = "Security group for MSK"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Kafka from EKS"
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  ingress {
    description     = "Kafka TLS from EKS"
    from_port       = 9094
    to_port         = 9094
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  ingress {
    description = "Zookeeper"
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-msk-sg"
  }
}

resource "aws_msk_cluster" "kafka" {
  cluster_name           = "${var.cluster_name}-kafka"
  kafka_version          = "3.5.1"
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = "kafka.m5.large"
    client_subnets  = module.vpc.private_subnets
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = 100
      }
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }

  tags = {
    Name        = "${var.cluster_name}-kafka"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${var.cluster_name}"
  retention_in_days = 7
}

# API Gateway (AWS API Gateway v2 - HTTP API) with VPC Link
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.cluster_name}-api"
  protocol_type = "HTTP"
  
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["*"]
    max_age       = 300
  }

  tags = {
    Name        = "${var.cluster_name}-api"
    Environment = var.environment
  }
}

resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = {
    Name        = "${var.cluster_name}-api-stage"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.cluster_name}"
  retention_in_days = 7
}

# Security group for VPC Link
resource "aws_security_group" "vpc_link" {
  name        = "${var.cluster_name}-vpc-link-sg"
  description = "Security group for API Gateway VPC Link"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Allow from API Gateway VPC Link"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    self            = true
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-vpc-link-sg"
  }
}

# VPC Link for API Gateway to connect to private EKS services
resource "aws_apigatewayv2_vpc_link" "main" {
  name               = "${var.cluster_name}-vpc-link"
  security_group_ids = [aws_security_group.vpc_link.id]
  subnet_ids         = module.vpc.private_subnets

  tags = {
    Name        = "${var.cluster_name}-vpc-link"
    Environment = var.environment
  }
}

# S3 Bucket for Logs and Artifacts
resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.cluster_name}-artifacts-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "${var.cluster_name}-artifacts"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM Role for EKS Service Accounts
resource "aws_iam_role" "eks_service_account" {
  name = "${var.cluster_name}-eks-service-account-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:sub" = "system:serviceaccount:default:job-scheduler-sa"
          "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "eks_service_account_s3" {
  name = "s3-access"
  role = aws_iam_role.eks_service_account.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.artifacts.arn,
        "${aws_s3_bucket.artifacts.arn}/*"
      ]
    }]
  })
}

### ----- EKS configuration ----- ###

# Karpenter Controller IAM Role
resource "aws_iam_role" "karpenter_controller" {
  name = "${var.cluster_name}-karpenter-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:sub" = "system:serviceaccount:karpenter:karpenter"
          "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name        = "${var.cluster_name}-karpenter-controller"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name = "karpenter-controller-policy"
  role = aws_iam_role.karpenter_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateTags",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
          "ec2:DeleteLaunchTemplate",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "pricing:GetProducts",
          "ssm:GetParameter"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = module.eks.eks_managed_node_groups["general"].iam_role_arn
      },
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = module.eks.cluster_arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage"
        ]
        Resource = aws_sqs_queue.karpenter_interruption.arn
      }
    ]
  })
}

# Karpenter Node IAM Role (reuse existing node role)
# Already created by EKS module, just need to add tags

# SQS Queue for Spot Instance Interruption Handling
resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${var.cluster_name}-karpenter-interruption"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = {
    Name        = "${var.cluster_name}-karpenter-interruption"
    Environment = var.environment
  }
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = [
          "events.amazonaws.com",
          "sqs.amazonaws.com"
        ]
      }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.karpenter_interruption.arn
    }]
  })
}

# EventBridge Rules for Spot Interruptions
resource "aws_cloudwatch_event_rule" "karpenter_spot_interruption" {
  name        = "${var.cluster_name}-karpenter-spot-interruption"
  description = "Karpenter Spot Instance Interruption Warning"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = {
    Name        = "${var.cluster_name}-karpenter-spot-interruption"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "karpenter_spot_interruption" {
  rule      = aws_cloudwatch_event_rule.karpenter_spot_interruption.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

# Instance State Change
resource "aws_cloudwatch_event_rule" "karpenter_instance_state_change" {
  name        = "${var.cluster_name}-karpenter-instance-state-change"
  description = "Karpenter Instance State Change"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })

  tags = {
    Name        = "${var.cluster_name}-karpenter-instance-state-change"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "karpenter_instance_state_change" {
  rule      = aws_cloudwatch_event_rule.karpenter_instance_state_change.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

# Rebalance Recommendation
resource "aws_cloudwatch_event_rule" "karpenter_rebalance" {
  name        = "${var.cluster_name}-karpenter-rebalance"
  description = "Karpenter Rebalance Recommendation"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })

  tags = {
    Name        = "${var.cluster_name}-karpenter-rebalance"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "karpenter_rebalance" {
  rule      = aws_cloudwatch_event_rule.karpenter_rebalance.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

# Outputs for Karpenter
output "karpenter_irsa_role_arn" {
  description = "Karpenter IRSA Role ARN"
  value       = aws_iam_role.karpenter_controller.arn
}

output "karpenter_sqs_queue_name" {
  description = "Karpenter SQS Queue Name"
  value       = aws_sqs_queue.karpenter_interruption.name
}


### ----- Security ----- ###
# KMS Key for Secrets Manager encryption
resource "aws_kms_key" "secrets_manager" {
  description             = "KMS key for Secrets Manager encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name        = "${var.cluster_name}-secrets-manager-key"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "secrets_manager" {
  name          = "alias/${var.cluster_name}-secrets-manager"
  target_key_id = aws_kms_key.secrets_manager.key_id
}

# AWS Secrets Manager for mTLS Certificates and Service Secrets
resource "aws_secretsmanager_secret" "mtls_ca_cert" {
  name                    = "${var.cluster_name}-mtls-ca-cert"
  description             = "Root CA certificate for mTLS"
  kms_key_id              = aws_kms_key.secrets_manager.arn
  recovery_window_in_days = 7

  tags = {
    Name        = "${var.cluster_name}-mtls-ca-cert"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret" "mtls_ca_key" {
  name                    = "${var.cluster_name}-mtls-ca-key"
  description             = "Root CA private key for mTLS"
  kms_key_id              = aws_kms_key.secrets_manager.arn
  recovery_window_in_days = 7

  tags = {
    Name        = "${var.cluster_name}-mtls-ca-key"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret" "account_provisioning_cert" {
  name                    = "${var.cluster_name}-account-provisioning-cert"
  description             = "Server certificate for Account Provisioning Service"
  kms_key_id              = aws_kms_key.secrets_manager.arn
  recovery_window_in_days = 7

  tags = {
    Name        = "${var.cluster_name}-account-provisioning-cert"
    Environment = var.environment
    Service     = "account-provisioning"
  }
}

resource "aws_secretsmanager_secret" "mcp_job_service_cert" {
  name                    = "${var.cluster_name}-mcp-job-service-cert"
  description             = "Server certificate for MCP Job Service"
  kms_key_id              = aws_kms_key.secrets_manager.arn
  recovery_window_in_days = 7

  tags = {
    Name        = "${var.cluster_name}-mcp-job-service-cert"
    Environment = var.environment
    Service     = "mcp-job-service"
  }
}

resource "aws_secretsmanager_secret" "argocd_cert" {
  name                    = "${var.cluster_name}-argocd-cert"
  description             = "Server certificate for ArgoCD"
  kms_key_id              = aws_kms_key.secrets_manager.arn
  recovery_window_in_days = 7

  tags = {
    Name        = "${var.cluster_name}-argocd-cert"
    Environment = var.environment
    Service     = "argocd"
  }
}

resource "aws_secretsmanager_secret" "jwt_signing_key" {
  name                    = "${var.cluster_name}-jwt-signing-key"
  description             = "JWT signing key for authentication"
  kms_key_id              = aws_kms_key.secrets_manager.arn
  recovery_window_in_days = 7

  tags = {
    Name        = "${var.cluster_name}-jwt-signing-key"
    Environment = var.environment
  }
}

# ACM Private Certificate Authority for mTLS
resource "aws_acmpca_certificate_authority" "mtls_ca" {
  type = "ROOT"

  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      common_name         = "${var.cluster_name}-mtls-ca"
      organizational_unit = "Platform Engineering"
      country             = "US"
    }
  }

  permanent_deletion_time_in_days = 7

  revocation_configuration {
    crl_configuration {
      enabled = false
    }
  }

  tags = {
    Name        = "${var.cluster_name}-mtls-ca"
    Environment = var.environment
  }
}

# Issue root CA certificate
resource "aws_acmpca_certificate" "mtls_ca_cert" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.mtls_ca.arn
  certificate_signing_request = aws_acmpca_certificate_authority.mtls_ca.certificate_signing_request
  signing_algorithm           = "SHA512WITHRSA"

  template_arn = "arn:aws:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = 10
  }
}

# Import the signed certificate back to the CA
resource "aws_acmpca_certificate_authority_certificate" "mtls_ca" {
  certificate_authority_arn = aws_acmpca_certificate_authority.mtls_ca.arn
  certificate               = aws_acmpca_certificate.mtls_ca_cert.certificate
  certificate_chain         = aws_acmpca_certificate.mtls_ca_cert.certificate_chain
}

# Data sources
data "aws_caller_identity" "current" {}