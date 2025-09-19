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
# Wait until the Ingress has a hostname (created by the ALB controller)
resource "null_resource" "wait_for_ingress_hostname" {
  count = var.enable_app ? 1 : 0

  provisioner "local-exec" {
    command = <<'EOT'
set -e
for i in $(seq 1 60); do
  host=$(kubectl -n statuspage get ingress statuspage -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [ -n "$host" ]; then
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

  depends_on = [helm_release.statuspage]  # keep this
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
data "aws_lb" "ingress" {
  count     = var.enable_app ? 1 : 0
  name       = local.alb_name
  #depends_on = [time_sleep.wait_for_alb]
  depends_on = [null_resource.wait_for_ingress_hostname]
}

# ---------------- lb.<domain> CNAME -> ALB DNS ------------------------------------#
resource "aws_route53_record" "lb_cname" {
  count   = var.enable_app ? 1 : 0
  zone_id = aws_route53_zone.this.zone_id
  name    = "lb.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60
  records = [local.ingress_hostname]

  #depends_on = [time_sleep.wait_for_alb]
  depends_on = [null_resource.wait_for_ingress_hostname]

}

# ------------------ Root A/ALIAS -> ALB ------------------------------------------#
resource "aws_route53_record" "root_alias" {
  count   = var.enable_app ? 1 : 0
  zone_id = aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = local.ingress_hostname
    zone_id                = data.aws_lb.ingress[0].zone_id
    evaluate_target_health = false
  }
  depends_on = [aws_route53_record.lb_cname]
}

# ------------------- www CNAME -> apex -----------------------------------------#
resource "aws_route53_record" "www_cname" {
  count   = var.enable_app ? 1 : 0
  zone_id = aws_route53_zone.this.zone_id
  name    = "www"
  type    = "CNAME"
  ttl     = 300
  records  = [var.domain_name]

  depends_on = [aws_route53_record.root_alias]
}
