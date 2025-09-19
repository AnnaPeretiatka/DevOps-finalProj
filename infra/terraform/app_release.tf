# ---------------------------- Get DB secret dynamically ---------------------------------------# 
data "aws_db_instance" "pg" {
  db_instance_identifier = module.db.db_instance_identifier
  depends_on = [module.db]
}

# Read the current password from Secrets Manager (JSON)
data "aws_secretsmanager_secret_version" "pg_master" {
  secret_id = data.aws_db_instance.pg.master_user_secret[0].secret_arn
  depends_on = [module.db]
}

locals {
  db_secret = jsondecode(data.aws_secretsmanager_secret_version.pg_master.secret_string)
  db_pass   = local.db_secret.password
  depends_on = [module.db]
}

# ---------------------------- Helm release for app ---------------------------------------# 

resource "helm_release" "statuspage" {
  count      = var.enable_app ? 1 : 0
  name             = "statuspage"
  namespace        = "statuspage"
  create_namespace = true
  chart            = "${path.module}/../helm/statuspage"   # path from infra/terraform -> infra/helm/statuspage

  wait             = false
  timeout          = 900       
  wait_for_jobs    = false         
  atomic           = false
  force_update   = true


  # ---------------------------- image.* 
  set {
    name  = "image.repository"
    value = "992382545251.dkr.ecr.us-east-1.amazonaws.com/status-page-ay-repo"
  }
  set {
    name  = "image.tag"
    value = "first"
  }

  # -------------------------- Core env
  set {
    name = "env.SECRET_KEY"
    value = random_password.secret_key.result
  }
  set {
    name = "env.REDIS_URL"
    value = "redis://statuspage-redis.statuspage.svc.cluster.local:6379/0"
  }
  set {
    name = "env.STATUS_HOSTNAME"
    value = "status-page-ay.com"
  }

  set {
    name  = "env.SITE_PROTOCOL"
    value = "http"
  }
  
  # ---------------------------- DB (from Secrets Manager)

  set_sensitive {
    name  = "env.DATABASE_URL"
    value = format(
        "postgresql://%s:%s@%s:%s/%s?sslmode=require",
        urlencode(var.db_username),
        urlencode(local.db_pass),
        module.db.db_instance_address,
        module.db.db_instance_port,
        module.db.db_instance_name
    )
  }
  
  set { 
    name = "env.db.host" 
    value = module.db.db_instance_address 
  }
  set { 
    name = "env.db.port" 
    value = module.db.db_instance_port 
  }
  set { 
    name = "env.db.name" 
    value = module.db.db_instance_name 
  }
  set { 
    name = "env.db.user" 
    value = var.db_username 
  }
  set_sensitive {
    name  = "env.db.password"
    value = local.db_pass
  }
  
  # ---------------------------- Ingress
  set {
    name = "ingress.enabled" 
    value = "true"
  }
  set {
    name = "ingress.className"
    value = "alb"
  }
  set {
    name = "ingress.hosts[0].host"
    value = "status-page-ay.com"
  }
  set {
    name = "ingress.hosts[0].paths[0].path"
    value = "/"
  }
  set {
    name = "ingress.hosts[0].paths[0].pathType"
    value = "Prefix"
  }

  # ---------------------------- S3
  set {
  name  = "s3.bucket"
  value = aws_s3_bucket.static.bucket
  }
  set {
    name  = "s3.region"
    value = var.aws_region
  }


  # app chart only installs after nodes exist and the ALB controller is ready
  # nodes ready so Pods can schedule | ALB controller watches Ingress | DB ready (its address resolves)
  depends_on = [
    aws_eks_node_group.default,   
    helm_release.alb,
    module.db
  ]
}
