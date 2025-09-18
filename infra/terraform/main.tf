data "aws_caller_identity" "current" {}

locals {
  tags = {
    Project = var.project_name
    Owner   = data.aws_caller_identity.current.arn
  }
}

# ------------------------------------------------ VPC ----------------------------------------------------

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
  public_subnet_tags      = { 
    "kubernetes.io/role/elb"                        = 1
    "kubernetes.io/cluster/${var.project_name}-eks" = "shared"
  }
  private_subnet_tags     = { 
    "kubernetes.io/role/internal-elb"               = 1
    "kubernetes.io/cluster/${var.project_name}-eks" = "shared"
  }
  tags                    = local.tags
}

# ------------------------------------------------ ECR ----------------------------------------------------

resource "aws_ecr_repository" "app" {
  name = "${var.project_name}-repo"
  image_scanning_configuration {
    scan_on_push = true
  }
  force_delete = true
  tags         = local.tags
}

# ------------------------------------------------ EKS Cluster ---------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.1.0"

  name               = "${var.project_name}-eks"
  kubernetes_version = var.cluster_version
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true
  
  endpoint_public_access  = true
  endpoint_private_access = false
  enable_irsa             = true

  encryption_config         = null
  create_kms_key            = false
  attach_encryption_policy  = false

  enabled_log_types         = []
  create_cloudwatch_log_group = false
  
  eks_managed_node_groups = {}
  addons                  = {}

  tags = local.tags
}

# ------------------------------------------------ EKS Add-ons (2/3) -----------------------------------------

resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "vpc-cni"
  tags                     = local.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name      = module.eks.cluster_name
  addon_name        = "kube-proxy"
  tags              = local.tags
}

# --------------------------------------------- Node Group IAM Role ---------------------------------------

resource "aws_iam_role" "node_role" {
  name = "${var.project_name}-ng-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action   = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# --------------------------------------------- Node Group ---------------------------------------

resource "aws_eks_node_group" "default" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "${var.project_name}-ec2"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = module.vpc.private_subnets

  scaling_config {
    desired_size = var.node_desired
    max_size     = var.node_max
    min_size     = var.node_min
  }

  ami_type       = "AL2_x86_64"
  instance_types = [var.node_instance_type]
  disk_size      = 20

  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy
  ]

  tags = local.tags
}

# ------------------------------------------------ EKS Add-ons (3/3) -----------------------------------------

resource "aws_eks_addon" "coredns" {
  cluster_name      = module.eks.cluster_name
  addon_name        = "coredns"
  depends_on   = [aws_eks_node_group.default]
  tags              = local.tags
}


# --------------------------------------------- DB-RDS ---------------------------------------

module "db" {
  source                        = "terraform-aws-modules/rds/aws"
  version                       = "~> 6.5"
  identifier                    = "${var.project_name}-pg"
  engine                        = "postgres"
  engine_version                = "16"
  family                        = "postgres16"
  instance_class                = "db.t4g.micro"
  allocated_storage             = var.db_allocated_storage
  db_name                       = "statuspage"
  username                      = var.db_username
  port                          = 5432
  multi_az                      = var.db_multi_az
  publicly_accessible           = false
  create_db_subnet_group        = true
  subnet_ids                    = module.vpc.private_subnets
  vpc_security_group_ids        = [aws_security_group.db.id]
  backup_window                 = "02:00-03:00"
  max_allocated_storage         = 100
  maintenance_window            = "Mon:03:00-Mon:04:00"
  deletion_protection           = false
  skip_final_snapshot           = true
  apply_immediately             = false
  manage_master_user_password   = true
  tags                          = local.tags
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "DB access"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_security_group_rule" "db_from_vpc" {
  type              = "ingress"
  security_group_id = aws_security_group.db.id
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  description       = "Allow Postgres from VPC"
}

resource "aws_security_group_rule" "db_from_eks_cluster_sg" {
  type                     = "ingress"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = module.eks.cluster_security_group_id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  description              = "Allow Postgres from EKS cluster SG"
}

# --------------------------------------------- Route53 ----------------------------------------------

resource "aws_route53_zone" "this" {
  name = var.domain_name
  tags = local.tags
}

# --------------------------------------------- S3 ----------------------------------------------

resource "aws_s3_bucket" "static" {
  bucket = "${var.project_name}-S3"
}

# Allow public reads for objects (quick start; later consider CloudFront)
resource "aws_s3_bucket_public_access_block" "pab" {
  bucket                  = aws_s3_bucket.static.id
  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "public_read" {
  statement {
    sid     = "PublicReadGetObject"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    principals { type = "*" identifiers = ["*"] }
    resources = ["${aws_s3_bucket.static.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "policy" {
  bucket = aws_s3_bucket.static.id
  policy = data.aws_iam_policy_document.public_read.json
}

output "bucket" {
  value = aws_s3_bucket.static.bucket
}
output "bucket_domain" {
  value = "s3.${var.region != null ? var.region : "us-east-1"}.amazonaws.com"
}

# ---------------------------- ACM_certificate - not prmissions error -------------------------------

/*
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
  validation_record_fqdns   = [for r in aws_route53_record.cert_validation : r.fqdn]
}
*/

# --------------------------------------------- GitHub ----------------------------------------------

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

/*
# --------------------------------------------- ALB - not used at ALL ----------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow inbound HTTP/HTTPS to ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

# Application Load Balancer
resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets
  tags               = local.tags
}


# Listener for HTTP (80)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "ALB is alive"
      status_code  = "200"
    }
  }
}

# Listener for HTTPS (443) - requires ACM cert - currently not working
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.cert.arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "ALB HTTPS is alive"
      status_code  = "200"
    }
  }
}
*/


# --------------------------------------------- WAF - not working ----------------------------------------------

/*
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
*/

# --------------------------------------------- Outputs ---------------------------------------

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

output "db_host" {
  value = module.db.db_instance_address
}

output "db_port" {
  value = module.db.db_instance_port
}

output "db_name" {
  value = module.db.db_instance_name
}

output "eks_cluster_sg_id" {
  value = module.eks.cluster_security_group_id
}

/*
output "acm_arn" {
  value = aws_acm_certificate_validation.cert.certificate_arn
}
*/
