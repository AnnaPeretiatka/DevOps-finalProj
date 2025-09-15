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
    type = string
    default = "ay.com"
}

variable "subdomain" { 
    type = string
    default = "status-page-ay"
}

/*
variable "db_password" { 
    type = string
}
*/