terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.project.aws_region

  default_tags {
    tags = {
      Project     = var.project.project_name
      ManagedBy   = "Terraform"
      Environment = var.project.environment
    }
  }
}

provider "helm" {
  kubernetes = {
    config_path = var.helm.use_existing_kubeconfig ? abspath(pathexpand(var.helm.kubeconfig_path)) : coalesce(module.k3s.kubeconfig_path, abspath(pathexpand(var.helm.kubeconfig_path)))
  }
}
