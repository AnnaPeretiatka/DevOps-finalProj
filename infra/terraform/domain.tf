# -------------------------- Locals ------------------#
locals {
  dc = var.domain_contact
}

# ---------- Register / Purchase the domain ----------#
/*
resource "aws_route53domains_domain" "this" {
  provider    = aws.use1
  domain_name = var.domain_name
  auto_renew  = false
  lifecycle { prevent_destroy = true }

  admin_privacy      = true
  registrant_privacy = true
  tech_privacy       = true
  billing_privacy    = true

  admin_contact {
    first_name      = local.dc.first_name
    last_name       = local.dc.last_name
    contact_type    = local.dc.contact_type
    email           = local.dc.email
    phone_number    = local.dc.phone_number
    address_line_1  = local.dc.address_line_1
    city            = local.dc.city
    country_code    = local.dc.country_code
    zip_code       = local.dc.zip_code
  }

  registrant_contact {
    first_name      = local.dc.first_name
    last_name       = local.dc.last_name
    contact_type    = local.dc.contact_type
    email           = local.dc.email
    phone_number    = local.dc.phone_number
    address_line_1  = local.dc.address_line_1
    city            = local.dc.city
    country_code    = local.dc.country_code
    zip_code       = local.dc.zip_code
  }

  tech_contact {
    first_name      = local.dc.first_name
    last_name       = local.dc.last_name
    contact_type    = local.dc.contact_type
    email           = local.dc.email
    phone_number    = local.dc.phone_number
    address_line_1  = local.dc.address_line_1
    city            = local.dc.city
    country_code    = local.dc.country_code
    zip_code       = local.dc.zip_code
  }

  billing_contact {
    first_name     = local.dc.first_name
    last_name      = local.dc.last_name
    contact_type   = local.dc.contact_type
    email          = local.dc.email
    phone_number   = local.dc.phone_number
    address_line_1 = local.dc.address_line_1
    city           = local.dc.city
    country_code   = local.dc.country_code
    zip_code       = local.dc.zip_code
  }

  # Point registrar at the hosted zone name servers
  dynamic "name_server" {
    for_each = aws_route53_zone.this.name_servers
    content {
      name = name_server.value
    }
  }
  tags = local.tags
}
*/

# ----->  ★ = If domain was creted before and not from terraform above

# -------------------------- https - ACM_certificate ----------------------------#
data "aws_route53_zone" "authoritative" {
  name         = var.domain_name
  zone_id = "Z00067461X470B5S2F567" # ★
  private_zone = false
}

resource "aws_acm_certificate" "site" {
  count             = var.enable_app ? 1 : 0
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"
   lifecycle {
    create_before_destroy = true
  }
  tags               = local.tags
}

resource "aws_route53_record" "cert_validation" {
  for_each = var.enable_app ? {
    for dvo in aws_acm_certificate.site[0].domain_validation_options :
    dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  } : {}

  zone_id = data.aws_route53_zone.authoritative.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.value]
}

resource "aws_acm_certificate_validation" "site" {
  count          = var.enable_app ? 1 : 0
  certificate_arn       = aws_acm_certificate.site[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

output "acm_arn" {
  value = var.enable_app ? aws_acm_certificate_validation.site[0].certificate_arn : null
}


# -------------------------- Outputs -------------------------#
output "route53_zone_id" {
  #value = aws_route53_zone.this.zone_id 
  value = data.aws_route53_zone.authoritative.zone_id # ★
}

output "route53_name_servers" {
  #value = aws_route53_zone.this.name_servers
  value = data.aws_route53_zone.authoritative.name_servers  # ★
}

output "status_hostname" {
  value = var.domain_name
}

# -------------------------- Fixed ALB name ------------------#
variable "alb_name_fixed" {
  type        = string
  description = "Deterministic ALB name used by the Ingress annotation"
  default     = "statuspage-ay-alb"
}


# ------------------------------------- IngressClass -------------------------------------
/*
resource "kubernetes_ingress_class" "alb" {
  count = var.enable_alb ? 1 : 0
  metadata {
    name = "alb"
  }
  spec {
    controller = "ingress.k8s.aws/alb"
  }
  depends_on = [
    helm_release.alb
  ]
}
*/

# ------------------------------------- Wait Ingress hostname -------------------------------------

# Ensure the controller & app chart are up before we query the Ingress status
/*
resource "time_sleep" "wait_for_alb" {
  count          = var.enable_app ? 1 : 0
  create_duration = "300s"
  depends_on      = [
    helm_release.statuspage,
    helm_release.alb
  ] 
}
*/

resource "null_resource" "wait_for_ingress_hostname" {
  count = var.enable_app ? 1 : 0

  # make sure controller + app/ingress exist first
  depends_on = [
    helm_release.alb,
    helm_release.statuspage
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command = <<-EOT
      set -euo pipefail
      for i in $(seq 1 60); do
        host=$(kubectl -n statuspage get ingress statuspage -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
        if [[ -n "$host" ]]; then
          echo "Ingress hostname ready: $host"
          exit 0
        fi
        echo "Waiting for ingress hostname (attempt $i/60)..."
        sleep 10
      done
      echo "Timeout waiting for ingress hostname"
      exit 1
    EOT
  }
}

# Pull the Ingress (once created by Helm)
data "kubernetes_ingress_v1" "statuspage" {
  count = var.enable_app ? 1 : 0
  metadata {
    name      = "statuspage"
    namespace = "statuspage"
  }
  #depends_on = [time_sleep.wait_for_alb]
  depends_on = [null_resource.wait_for_ingress_hostname]
}

# ---------------- Parse ALB name from the Ingress hostname (k8s-... from k8s-....elb.amazonaws.com)
locals {
  ingress_hostname = try(
    data.kubernetes_ingress_v1.statuspage[0].status[0].load_balancer[0].ingress[0].hostname,
    ""
  )
  alb_label       = local.ingress_hostname != "" ? split(".", local.ingress_hostname)[0] : ""
  alb_suffix_list = local.alb_label != "" ? regexall("-[0-9]+$", local.alb_label) : []
  alb_suffix      = length(local.alb_suffix_list) > 0 ? local.alb_suffix_list[0] : ""
  alb_name        = local.alb_label != "" ? replace(local.alb_label, local.alb_suffix, "") : null
}

# ---------------- get ALB - dns_name + original hosted zone id -------------------#
/*
data "aws_lb" "ingress" {
  count     = var.enable_app ? 1 : 0
  name       = local.alb_name
  #depends_on = [time_sleep.wait_for_alb]
  depends_on = [null_resource.wait_for_ingress_hostname]
}
*/

# Get the canonical hosted-zone ID for ALBs in this region
data "aws_lb_hosted_zone_id" "alb" {
  region              = var.aws_region
  load_balancer_type  = "application"
}

# ---------------- lb.<domain> CNAME -> ALB DNS ------------------------------------#
resource "aws_route53_record" "lb_cname" {
  count   = var.enable_app ? 1 : 0
  #zone_id = aws_route53_zone.this.zone_id
  zone_id = data.aws_route53_zone.authoritative.zone_id  # ★
  name    = "lb.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60
  #records = [local.ingress_hostname]
  records = [
    data.kubernetes_ingress_v1.statuspage[0].status[0].load_balancer[0].ingress[0].hostname
  ]

  #depends_on = [time_sleep.wait_for_alb]
  depends_on = [null_resource.wait_for_ingress_hostname]

}

# ------------------ Root A/ALIAS -> ALB ------------------------------------------#
resource "aws_route53_record" "root_alias" {
  count   = var.enable_app ? 1 : 0
  #zone_id = aws_route53_zone.this.zone_id
  zone_id = data.aws_route53_zone.authoritative.zone_id  # ★
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = data.kubernetes_ingress_v1.statuspage[0].status[0].load_balancer[0].ingress[0].hostname
    zone_id                = data.aws_lb_hosted_zone_id.alb.id
    #name                   = aws_route53_record.lb_cname[0].fqdn
    #zone_id                = data.aws_route53_zone.authoritative.zone_id
    evaluate_target_health = false
  }
  depends_on = [aws_route53_record.lb_cname]
}

# ------------------- www CNAME -> apex -----------------------------------------#
resource "aws_route53_record" "www_cname" {
  count   = var.enable_app ? 1 : 0
  #zone_id = aws_route53_zone.this.zone_id
  zone_id = data.aws_route53_zone.authoritative.zone_id  # ★
  name    = "www"
  type    = "CNAME"
  ttl     = 300
  records  = [var.domain_name]

  depends_on = [aws_route53_record.root_alias]
}
