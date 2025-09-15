locals {
  dc = var.domain_contact
}

# Register/purchase the domain
resource "aws_route53domains_domain" "this" {
  #count       = var.register_domain ? 1 : 0
  provider    = aws.use1
  domain_name = var.domain_name
  auto_renew  = false
  lifecycle { prevent_destroy = true }

  admin_privacy      = true
  registrant_privacy = true
  tech_privacy       = true
  billing_privacy    = true

  # same contact for all 4 roles

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

# outputs
output "route53_zone_id" {
  value = aws_route53_zone.this.zone_id
}

output "route53_name_servers" {
  value = aws_route53_zone.this.name_servers
}

output "status_hostname" {
  value = var.domain_name
}

# ------------------------------------- DNS records -> Ingress/ALB -------------------------------------

# Make sure the Ingress exists (helm upgrade/install) BEFORE terraform apply.
resource "time_sleep" "wait_for_alb" {
  create_duration = "60s"
  depends_on      = [helm_release.statuspage]
}

data "kubernetes_ingress_v1" "statuspage" {
  metadata {
    name      = "statuspage"
    namespace = "statuspage"
  }
  depends_on = [time_sleep.wait_for_alb]
}

# Parse ALB name from the Ingress hostname (k8s-... from k8s-....elb.amazonaws.com)
locals {
  alb_hostname = data.kubernetes_ingress_v1.statuspage.status[0].load_balancer[0].ingress[0].hostname
  alb_label    = split(".", local.alb_hostname)[0]                                      # k8s-...-3cbb543552-303246783
  alb_suffix_list = regexall("-[0-9]+$", local.alb_label)                               # ["-303246783"]
  alb_suffix      = length(local.alb_suffix_list) > 0 ? local.alb_suffix_list[0] : ""
  alb_name        = replace(local.alb_label, local.alb_suffix, "")                      # k8s-statuspa-statuspa-3cbb543552
}

# get ALB - dns_name + original hosted zone id
data "aws_lb" "ingress" {
  name       = local.alb_name
  depends_on = [time_sleep.wait_for_alb]
}

# lb.<domain> -> ALB DNS from Ingress status (CNAME)
resource "aws_route53_record" "lb_cname" {
  zone_id = aws_route53_zone.this.zone_id
  name    = "lb.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60
  records = [local.alb_hostname]

  depends_on = [data.kubernetes_ingress_v1.statuspage, time_sleep.wait_for_alb]
}

# A/ALIAS at root -> ALB
resource "aws_route53_record" "root_alias" {
  zone_id = aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = data.aws_lb.ingress.dns_name
    zone_id                = data.aws_lb.ingress.zone_id
    evaluate_target_health = false
  }
  depends_on = [aws_route53_record.lb_cname]
}

# www -> apex
resource "aws_route53_record" "www_cname" {
  zone_id = aws_route53_zone.this.zone_id
  name    = "www"
  type    = "CNAME"
  ttl     = 300
  records = [var.domain_name]

  depends_on = [aws_route53_record.root_alias]
}