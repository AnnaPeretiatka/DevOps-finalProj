# -------------------------- Locals ------------------#
locals {
  dc = var.domain_contact
}

# ---------- Register / Purchase the domain ----------#

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

# -------------------------- Outputs -------------------------#
output "route53_zone_id" {
  value = aws_route53_zone.this.zone_id
}

output "route53_name_servers" {
  value = aws_route53_zone.this.name_servers
}

output "status_hostname" {
  value = var.domain_name
}

# ------------------------------------- Wait for ALB Controller + App Ingress -------------------------------------

# Ensure the controller & app chart are up before we query the Ingress status
resource "time_sleep" "wait_for_alb" {
  create_duration = "180s"
  depends_on      = [
    helm_release.statuspage,
    helm_release.alb
  ]
}

# Pull the Ingress (once created by Helm)
data "kubernetes_ingress_v1" "statuspage" {
  metadata {
    name      = "statuspage"
    namespace = "statuspage"
  }
  depends_on = [time_sleep.wait_for_alb]
}

# Parse ALB name from the Ingress hostname (k8s-... from k8s-....elb.amazonaws.com)
locals {
  ingress_hostname = try(
    data.kubernetes_ingress_v1.statuspage.status[0].load_balancer[0].ingress[0].hostname,
    ""
  )
  # Example hostname: k8s-statuspa-statuspa-3cbb543552-1616844995.us-east-1.elb.amazonaws.com
  alb_label       = local.ingress_hostname != "" ? split(".", local.ingress_hostname)[0] : ""
  alb_suffix_list = local.alb_label != "" ? regexall("-[0-9]+$", local.alb_label) : []
  alb_suffix      = length(local.alb_suffix_list) > 0 ? local.alb_suffix_list[0] : ""
  alb_name        = local.alb_label != "" ? replace(local.alb_label, local.alb_suffix, "") : ""
}

# ---------------- get ALB - dns_name + original hosted zone id -------------------#
data "aws_lb" "ingress" {
  name       = local.alb_name
  depends_on = [time_sleep.wait_for_alb]
}

# ---------------- lb.<domain> CNAME -> ALB DNS ------------------------------------#
resource "aws_route53_record" "lb_cname" {
  zone_id = aws_route53_zone.this.zone_id
  name    = "lb.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60
  records = [local.ingress_hostname]

  depends_on = [
    data.kubernetes_ingress_v1.statuspage,
    time_sleep.wait_for_alb
  ]
}

# ------------------ Root A/ALIAS -> ALB ------------------------------------------#
resource "aws_route53_record" "root_alias" {
  zone_id = aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = local.ingress_hostname
    zone_id                = data.aws_lb.ingress.zone_id
    evaluate_target_health = false
  }
  depends_on = [aws_route53_record.lb_cname]
}

# ------------------- www CNAME -> apex -----------------------------------------#
resource "aws_route53_record" "www_cname" {
  zone_id = aws_route53_zone.this.zone_id
  name    = "www"
  type    = "CNAME"
  ttl     = 300
  records  = [var.domain_name]

  depends_on = [aws_route53_record.root_alias]
}
