variable "project_name" { 
    type = string
    default = "status-page-ay" 
}

variable "aws_region" { 
    type = string
    default = "us-east-1"
}

variable "cluster_version" { 
    type = string
    default = "1.30"
}

variable "node_instance_type" { 
    type = string
    default = "t3.small"
}

variable "node_desired" { 
    type = number
    default = 4
}

variable "node_min" { 
    type = number
    default = 4
}

variable "node_max" { 
    type = number
    default = 6
}

variable "db_username" { 
    type = string
    default = "statuspage"
}

variable "db_allocated_storage" { 
    type = number
    default = 20
}

variable "db_multi_az" { 
    type = bool
    default = true
}

variable "domain_name" { 
    description = "Root domain to register and use"
    type = string
}

variable "register_domain" {
  description = "If true, Terraform will purchase/register the domain"
  type        = bool
  default     = false
}

variable "domain_contact" {
  description = "Contact used for admin/registrant/tech (all three). Phone in E.164 (e.g., +972...)."
  type = object({
    first_name     : string
    last_name      : string
    contact_type   : string     
    email          : string
    phone_number   : string     
    address_line_1 : string
    address_line_2 : optional(string)
    city           : string
    state          : optional(string) 
    country_code   : string           
    zip_code       : optional(string)
  })
}

/*
variable "subdomain" { 
    type = string
    default = "status-page-ay"
}

variable "db_password" { 
    type = string
}
*/