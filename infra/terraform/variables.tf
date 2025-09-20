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

#variable "secret_key" {
#  type = string
#  description = "Django SECRET_KEY"
#}

variable "redis_url" {
  type        = string
  description = "Redis connection URL"
  default     = "redis://statuspage-redis.statuspage.svc.cluster.local:6379/0"
}

variable "enable_alb" {
  type    = bool
  default = false
}

variable "enable_app" {
  type    = bool
  default = false
}

variable "image_tag" {
  type        = string
  description = "Container image tag to deploy"
  default     = "latest"
}

variable "domain_contact" {
  description = "Contact used for admin/registrant/tech (all three)"
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



