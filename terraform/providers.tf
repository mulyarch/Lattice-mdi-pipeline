# ═══════════════════════════════════════════════════════════════════════════════
# PROVIDERS — Multi-Cloud Configuration
# AWS (Sovereign) + Azure (Allied) + Kubernetes
# ═══════════════════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# ─────────────────────────────────────────────
# AWS Provider — Sovereign Environment
# ─────────────────────────────────────────────

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "anduril-mdi-pipeline"
    }
  }
}

# ─────────────────────────────────────────────
# Azure Provider — Allied Environment
# ─────────────────────────────────────────────

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }

  subscription_id = var.azure_subscription_id
}

# ─────────────────────────────────────────────
# Kubernetes Provider — EKS (configured after cluster creation)
# ─────────────────────────────────────────────

provider "kubernetes" {
  alias = "eks"

  host                   = module.aws_sovereign.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.aws_sovereign.eks_cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.aws_sovereign.eks_cluster_name]
  }
}

# ─────────────────────────────────────────────
# Kubernetes Provider — AKS (configured after cluster creation)
# ─────────────────────────────────────────────

provider "kubernetes" {
  alias = "aks"

  host                   = module.azure_allied.aks_cluster_host
  client_certificate     = base64decode(module.azure_allied.aks_client_certificate)
  client_key             = base64decode(module.azure_allied.aks_client_key)
  cluster_ca_certificate = base64decode(module.azure_allied.aks_cluster_ca_certificate)
}
