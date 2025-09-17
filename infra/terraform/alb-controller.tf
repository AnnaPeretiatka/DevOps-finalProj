# -------- IRSA: trust the cluster's OIDC provider --------

data "aws_iam_openid_connect_provider" "eks" {
  arn = module.eks.oidc_provider_arn
}

locals {
  # Example: "https://oidc.eks.us-east-1.amazonaws.com/id/ABCDEFG"
  oidc_issuer_url_no_https = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
}

resource "aws_iam_role" "alb_irsa" {
  name = "${var.project_name}-alb-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.eks.arn
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${local.oidc_issuer_url_no_https}:aud" = "sts.amazonaws.com",
          # This MUST match the ServiceAccount we ask Helm to create below
          "${local.oidc_issuer_url_no_https}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })

  tags = local.tags
}

# -------- Policy for the controller --------
# Condensed policy for standard ALB/NLB Ingress use
resource "aws_iam_policy" "alb_policy" {
  name = "${var.project_name}-alb-controller-policy"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "elasticloadbalancing:Describe*",
        "iam:ListServerCertificates",
        "iam:GetServerCertificate",
        "cognito-idp:DescribeUserPoolClient",
        "waf-regional:GetWebACLForResource",
        "waf-regional:GetWebACL",
        "waf-regional:AssociateWebACL",
        "waf-regional:DisassociateWebACL",
        "wafv2:GetWebACLForResource",
        "wafv2:GetWebACL",
        "wafv2:AssociateWebACL",
        "wafv2:DisassociateWebACL",
        "shield:GetSubscriptionState",
        "shield:DescribeProtection",
        "shield:CreateProtection",
        "shield:DeleteProtection"
      ],
      "Resource": "*"
    },
    { "Effect": "Allow",
      "Action": [
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:CreateSecurityGroup",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DeleteSecurityGroup"
      ],
      "Resource": "*"
    },
    { "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:*"
      ],
      "Resource": "*"
    }
  ]
}
POLICY

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "alb_attach" {
  role       = aws_iam_role.alb_irsa.name
  policy_arn = aws_iam_policy.alb_policy.arn
}

# -------- Helm install: let Helm CREATE the SA + annotate it with our IRSA role --------

resource "helm_release" "alb" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  # version   = "1.9.0" # (optional) pin a version if you want

  # Cluster details
  set {
    name = "clusterName"
    value = module.eks.cluster_name
  }

  set { 
    name = "region"
    value = var.aws_region 
  }

  set { 
    name = "vpcId"
    value = module.vpc.vpc_id
  }

  # ServiceAccount managed by Helm
  set { 
    name = "serviceAccount.create"
    value = "true"
  }

  set { 
    name = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  # IRSA annotation: need to escape the dots in the key for Terraform
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.alb_irsa.arn
  }

  # Ensure IAM bits exist before install
  #chart doesn’t install before a schedulable node exists
  depends_on = [
    aws_iam_role_policy_attachment.alb_attach,
    aws_eks_node_group.default  
  ]
}

resource "helm_release" "ttl_after_finished" {
  name       = "ttl-after-finished"
  namespace  = "kube-system"
  repository = "https://charts.deliveryhero.io/"
  chart      = "k8s-ttl-controller"
  version    = "0.5.0" # adjust if newer available

  set {
    name  = "rbac.create"
    value = "true"
  }
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.11.0" # check latest
  values = [<<EOT
args:
  - --kubelet-insecure-tls
  - --kubelet-preferred-address-types=InternalIP
EOT
  ]
}