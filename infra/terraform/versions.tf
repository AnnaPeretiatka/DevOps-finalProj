terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.9.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.29"   # any recent 2.x is fine
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"   # any recent 2.x is fine
    }
  }
}