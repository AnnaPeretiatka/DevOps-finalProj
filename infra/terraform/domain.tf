locals {
  dc = var.domain_contact
}

# Public hosted zone for the domain
resource "aws_route53_zone" "this" {
  name = var.domain_name
  tags = local.tags
}

# Register/purchase the domain
resource "aws_route53domains_domain" "this" {
  provider    = aws.use1
  domain_name = var.domain_name
  auto_renew  = false

  # Use of same contact for all three roles
  admin_contact {
    first_name      = local.dc.first_name
    last_name       = local.dc.last_name
    contact_type    = local.dc.contact_type
    email           = local.dc.email
    phone_number    = local.dc.phone_number
    address_line_1  = local.dc.address_line_1
    city            = local.dc.city
    country_code    = local.dc.country_code
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
  }

  admin_privacy      = true
  registrant_privacy = true
  tech_privacy       = true

  # Point registrar at the hosted zone name servers
  dynamic "name_server" {
    for_each = aws_route53_zone.this.name_servers
    content {
      name = name_server.value
    }
  }

  tags = local.tags
}

# Helpful outputs
output "route53_zone_id" {
  value = aws_route53_zone.this.zone_id
}

output "route53_name_servers" {
  value = aws_route53_zone.this.name_servers
}

output "status_hostname" {
  value = var.domain_name
}