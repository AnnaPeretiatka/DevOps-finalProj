data "aws_caller_identity" "current" {}

locals {
  tags = {
    Project = var.project_name
    Owner   = data.aws_caller_identity.current.arn
  }
}

module "vpc" {
  source                  = "terraform-aws-modules/vpc/aws"
  version                 = "~> 5.1"
  name                    = "${var.project_name}-vpc"
  cidr                    = "10.1.0.0/16"
  azs                     = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnets          = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnets         = ["10.1.11.0/24", "10.1.12.0/24"]
  enable_nat_gateway      = true
  single_nat_gateway      = false
  one_nat_gateway_per_az  = true
  enable_dns_hostnames    = true
  enable_dns_support      = true
  public_subnet_tags      = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags     = { "kubernetes.io/role/internal-elb" = 1 }
  tags                    = local.tags
}

resource "aws_ecr_repository" "app" {
  name = "${var.project_name}-repo"
  image_scanning_configuration {
    scan_on_push = true
  }
  force_delete = true
  tags         = local.tags
}

module "eks" {
  source                        = "terraform-aws-modules/eks/aws"
  version                       = "~> 20.8"
  cluster_name                  = "${var.project_name}-eks"
  cluster_version               = var.cluster_version
  vpc_id                        = module.vpc.vpc_id
  subnet_ids                    = module.vpc.private_subnets
  cluster_endpoint_public_access = true
  enable_irsa                   = true
  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      desired_size   = var.node_desired
      min_size       = var.node_min
      max_size       = var.node_max
      subnet_ids     = module.vpc.private_subnets
    }
  }
  tags = local.tags
}

module "db" {
  source                   = "terraform-aws-modules/rds/aws"
  version                  = "~> 6.5"
  identifier               = "${var.project_name}-pg"
  engine                   = "postgres"
  engine_version           = "16"
  family                   = "postgres16"
  instance_class           = "db.t4g.micro"
  allocated_storage        = var.db_allocated_storage
  db_name                  = "statuspage"
  username                 = var.db_username
  password                 = var.db_password
  port                     = 5432
  multi_az                 = var.db_multi_az
  publicly_accessible      = false
  create_db_subnet_group   = true
  subnet_ids               = module.vpc.private_subnets
  vpc_security_group_ids   = [aws_security_group.db.id]
  backup_window            = "02:00-03:00"
  maintenance_window       = "Mon:03:00-Mon:04:00"
  deletion_protection      = false
  skip_final_snapshot      = false
  tags                     = local.tags
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "DB access"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.1.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_route53_zone" "this" {
  name         = var.domain_name
  zone_type = "Public"
  tags               = local.tags
}

resource "aws_acm_certificate" "cert" {
  domain_name        = "${var.subdomain}.${var.domain_name}"
  validation_method  = "DNS"
  lifecycle {
    create_before_destroy = true
  }
  tags               = local.tags
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  zone_id = aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn           = aws_acm_certificate.cert.arn
  validation_record_fqdns   = [for r in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_iam_openid_connect_provider" "github" {
  url              = "https://token.actions.githubusercontent.com"
  client_id_list   = ["sts.amazonaws.com"]
  thumbprint_list  = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.project_name}-github-deploy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        },
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:*:*"
        }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_policy" "deploy_policy" {
  name   = "${var.project_name}-deploy-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["eks:DescribeCluster"],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = ["ecr:GetAuthorizationToken"],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories"
        ],
        Resource = aws_ecr_repository.app.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_deploy_attach" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = aws_iam_policy.deploy_policy.arn
}

resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.db.id] # or another SG
  subnets            = module.vpc.public_subnets
  tags               = local.tags
}

resource "aws_wafv2_web_acl" "alb_waf" {
  name        = "${var.project_name}-waf"
  description = "WAF for public ALB"
  scope       = "REGIONAL"
  default_action {
    allow {}
  }
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "waf"
      sampled_requests_enabled   = true
    }
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "waf"
    sampled_requests_enabled   = true
  }
  tags = local.tags
}

resource "aws_wafv2_web_acl_association" "alb_waf_assoc" {
  resource_arn = aws_lb.app.arn
  web_acl_arn  = aws_wafv2_web_acl.alb_waf.arn
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}
output "cluster_name" {
  value = module.eks.cluster_name
}
output "aws_region" {
  value = var.aws_region
}
output "vpc_id" {
  value = module.vpc.vpc_id
}
output "private_subnets" {
  value = module.vpc.private_subnets
}
output "public_subnets" {
  value = module.vpc.public_subnets
}
output "ecr_repo_url" {
  value = aws_ecr_repository.app.repository_url
}
output "rds_endpoint" {
  value = module.db.db_instance_endpoint
}
output "acm_arn" {
  value = aws_acm_certificate_validation.cert.certificate_arn
}
