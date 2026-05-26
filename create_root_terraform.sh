#!/bin/bash
# Run from the root of your anduril-mdi-pipeline directory
# This creates the root Terraform configuration files

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 1: terraform/providers.tf
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/providers.tf << 'EOF'
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
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 2: terraform/backend.tf
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/backend.tf << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# BACKEND — Remote State Storage
# S3 backend with DynamoDB locking for team collaboration
# State is encrypted at rest with KMS
# ═══════════════════════════════════════════════════════════════════════════════

terraform {
  backend "s3" {
    bucket         = "aws-terraform-state-bucket-0011"
    key            = "sovereign-infra/terraform.tfstate"  # Overridden per environment in CI/CD
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"

    # Uncomment for KMS encryption of state file
    # kms_key_id = "alias/terraform-state-key"
  }
}
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 3: terraform/main.tf
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/main.tf << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# ROOT MODULE — Sovereign Multi-Cloud Infrastructure
# Orchestrates all child modules to build the complete architecture:
#
#   1. AWS Sovereign Environment (VPC, EKS, KMS, S3, GuardDuty)
#   2. Azure Allied Environment (VNet, AKS, Key Vault)
#   3. Cross-Cloud VPN (IPsec Site-to-Site)
#
# Architecture:
#   ┌─────────────────┐       IPsec VPN       ┌─────────────────┐
#   │  AWS Sovereign  │◄═════════════════════►│  Azure Allied   │
#   │  us-east-1      │                       │  australiaeast  │
#   │                 │                       │                 │
#   │  • VPC          │                       │  • VNet         │
#   │  • EKS          │                       │  • AKS          │
#   │  • KMS + S3     │                       │  • Key Vault    │
#   │  • GuardDuty    │                       │  • NSGs         │
#   └─────────────────┘                       └─────────────────┘
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# DATA SOURCES
# ─────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─────────────────────────────────────────────
# MODULE 1: AWS Sovereign Environment
# ─────────────────────────────────────────────

module "aws_sovereign" {
  source = "./modules/aws-sovereign"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  vpc_cidr           = var.aws_vpc_cidr
  availability_zones = var.aws_availability_zones

  # EKS Configuration
  eks_cluster_version    = var.eks_cluster_version
  eks_node_instance_type = var.eks_node_instance_type
  eks_node_min_size      = var.eks_node_min_size
  eks_node_max_size      = var.eks_node_max_size
  eks_node_desired_size  = var.eks_node_desired_size

  # Tags
  tags = local.common_tags
}

# ─────────────────────────────────────────────
# MODULE 2: Azure Allied Environment
# ─────────────────────────────────────────────

module "azure_allied" {
  source = "./modules/azure-allied"

  project_name        = var.project_name
  environment         = var.environment
  azure_region        = var.azure_region
  vnet_cidr           = var.azure_vnet_cidr
  azure_subscription_id = var.azure_subscription_id

  # AKS Configuration
  aks_kubernetes_version = var.aks_kubernetes_version
  aks_node_vm_size       = var.aks_node_vm_size
  aks_node_min_count     = var.aks_node_min_count
  aks_node_max_count     = var.aks_node_max_count

  tags = local.common_tags
}

# ─────────────────────────────────────────────
# MODULE 3: Cross-Cloud VPN (AWS ↔ Azure)
# ─────────────────────────────────────────────

module "cross_cloud_vpn" {
  source = "./modules/cross-cloud-vpn"

  project_name = var.project_name
  environment  = var.environment

  # AWS Side
  aws_vpc_id                 = module.aws_sovereign.vpc_id
  aws_vpc_cidr               = var.aws_vpc_cidr
  aws_private_route_table_id = module.aws_sovereign.private_route_table_id
  aws_intra_route_table_id   = module.aws_sovereign.intra_route_table_id
  aws_bgp_asn                = var.aws_bgp_asn
  aws_sns_topic_arn          = module.aws_sovereign.sns_topic_arn

  # Azure Side
  azure_region                       = var.azure_region
  azure_resource_group_name          = module.azure_allied.resource_group_name
  azure_gateway_subnet_id            = module.azure_allied.gateway_subnet_id
  azure_vnet_cidr                    = var.azure_vnet_cidr
  azure_bgp_asn                      = var.azure_bgp_asn
  azure_log_analytics_workspace_id   = module.azure_allied.log_analytics_workspace_id

  # VPN Secrets (from GitHub Secrets via CI/CD)
  vpn_preshared_key_tunnel1 = var.vpn_preshared_key_tunnel1
  vpn_preshared_key_tunnel2 = var.vpn_preshared_key_tunnel2

  depends_on = [
    module.aws_sovereign,
    module.azure_allied,
  ]
}

# ─────────────────────────────────────────────
# LOCAL VALUES
# ─────────────────────────────────────────────

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "anduril-mdi-pipeline"
    Owner       = "yuriy"
  }

  aws_account_id = data.aws_caller_identity.current.account_id
}
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 4: terraform/variables.tf
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/variables.tf << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# ROOT VARIABLES — Sovereign Multi-Cloud Infrastructure
# These are the top-level inputs passed to child modules
# Values come from terraform.tfvars (per environment) or CI/CD variables
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# GENERAL
# ─────────────────────────────────────────────

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "mdi-sovereign"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# ─────────────────────────────────────────────
# AWS CONFIGURATION
# ─────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region for sovereign environment"
  type        = string
  default     = "us-east-1"
}

variable "aws_vpc_cidr" {
  description = "CIDR block for the AWS sovereign VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.aws_vpc_cidr, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "aws_availability_zones" {
  description = "List of availability zones for the AWS VPC"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "aws_bgp_asn" {
  description = "BGP ASN for AWS VPN Gateway"
  type        = number
  default     = 64512
}

# ─────────────────────────────────────────────
# AWS EKS CONFIGURATION
# ─────────────────────────────────────────────

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.29"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "eks_node_min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 5
}

variable "eks_node_desired_size" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2
}

# ─────────────────────────────────────────────
# AZURE CONFIGURATION
# ─────────────────────────────────────────────

variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "azure_region" {
  description = "Azure region for allied environment"
  type        = string
  default     = "australiaeast"
}

variable "azure_vnet_cidr" {
  description = "CIDR block for the Azure allied VNet"
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrhost(var.azure_vnet_cidr, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "azure_bgp_asn" {
  description = "BGP ASN for Azure VPN Gateway"
  type        = number
  default     = 65515
}

# ─────────────────────────────────────────────
# AZURE AKS CONFIGURATION
# ─────────────────────────────────────────────

variable "aks_kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.29"
}

variable "aks_node_vm_size" {
  description = "VM size for AKS worker nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "aks_node_min_count" {
  description = "Minimum number of AKS worker nodes"
  type        = number
  default     = 2
}

variable "aks_node_max_count" {
  description = "Maximum number of AKS worker nodes"
  type        = number
  default     = 5
}

# ─────────────────────────────────────────────
# VPN CONFIGURATION
# ─────────────────────────────────────────────

variable "vpn_preshared_key_tunnel1" {
  description = "Pre-shared key for VPN tunnel 1 (min 32 characters)"
  type        = string
  sensitive   = true
  default     = "REPLACE_WITH_SECURE_KEY_MIN_32_CHARS_LONG_1"

  validation {
    condition     = length(var.vpn_preshared_key_tunnel1) >= 32
    error_message = "Pre-shared key must be at least 32 characters."
  }
}

variable "vpn_preshared_key_tunnel2" {
  description = "Pre-shared key for VPN tunnel 2 (min 32 characters)"
  type        = string
  sensitive   = true
  default     = "REPLACE_WITH_SECURE_KEY_MIN_32_CHARS_LONG_2"

  validation {
    condition     = length(var.vpn_preshared_key_tunnel2) >= 32
    error_message = "Pre-shared key must be at least 32 characters."
  }
}
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 5: terraform/outputs.tf
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/outputs.tf << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# ROOT OUTPUTS — Sovereign Multi-Cloud Infrastructure
# These outputs are displayed after terraform apply and used by CI/CD
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# AWS SOVEREIGN OUTPUTS
# ─────────────────────────────────────────────

output "aws_vpc_id" {
  description = "ID of the AWS sovereign VPC"
  value       = module.aws_sovereign.vpc_id
}

output "aws_vpc_cidr" {
  description = "CIDR of the AWS sovereign VPC"
  value       = var.aws_vpc_cidr
}

output "aws_eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.aws_sovereign.eks_cluster_name
}

output "aws_eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.aws_sovereign.eks_cluster_endpoint
  sensitive   = true
}

output "aws_eks_cluster_version" {
  description = "EKS cluster Kubernetes version"
  value       = module.aws_sovereign.eks_cluster_version
}

output "aws_s3_bucket_name" {
  description = "Name of the encrypted mission data S3 bucket"
  value       = module.aws_sovereign.s3_bucket_name
}

output "aws_kms_key_arn" {
  description = "ARN of the KMS key for data encryption"
  value       = module.aws_sovereign.kms_key_arn
  sensitive   = true
}

# ─────────────────────────────────────────────
# AZURE ALLIED OUTPUTS
# ─────────────────────────────────────────────

output "azure_resource_group_name" {
  description = "Name of the Azure resource group"
  value       = module.azure_allied.resource_group_name
}

output "azure_vnet_id" {
  description = "ID of the Azure allied VNet"
  value       = module.azure_allied.vnet_id
}

output "azure_aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.azure_allied.aks_cluster_name
}

output "azure_key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = module.azure_allied.key_vault_uri
  sensitive   = true
}

# ─────────────────────────────────────────────
# CROSS-CLOUD VPN OUTPUTS
# ─────────────────────────────────────────────

output "vpn_tunnel_status" {
  description = "VPN tunnel configuration summary"
  value       = module.cross_cloud_vpn.vpn_tunnel_status
}

output "vpn_aws_gateway_id" {
  description = "AWS VPN Gateway ID"
  value       = module.cross_cloud_vpn.aws_vpn_gateway_id
}

output "vpn_azure_gateway_ip" {
  description = "Azure VPN Gateway public IP"
  value       = module.cross_cloud_vpn.azure_vpn_gateway_public_ip
}

# ─────────────────────────────────────────────
# DEPLOYMENT SUMMARY
# ─────────────────────────────────────────────

output "deployment_summary" {
  description = "Complete deployment summary"
  value = {
    project     = var.project_name
    environment = var.environment

    aws = {
      region       = var.aws_region
      vpc_cidr     = var.aws_vpc_cidr
      eks_cluster  = module.aws_sovereign.eks_cluster_name
      eks_version  = module.aws_sovereign.eks_cluster_version
    }

    azure = {
      region       = var.azure_region
      vnet_cidr    = var.azure_vnet_cidr
      aks_cluster  = module.azure_allied.aks_cluster_name
    }

    vpn = {
      encryption = "AES-256 / IKEv2"
      routing    = "BGP"
      tunnels    = 2
    }

    security = {
      encryption_at_rest  = "KMS (AWS) + Key Vault (Azure)"
      encryption_in_transit = "TLS 1.2+ / IPsec"
      network_isolation   = "Private subnets + NSGs + NetworkPolicies"
      identity            = "IRSA (AWS) + Workload Identity (Azure)"
      monitoring          = "GuardDuty + CloudWatch + Azure Monitor"
    }
  }
}
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 6: terraform/versions.tf (DynamoDB lock table for state)
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/state-resources/main.tf << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# STATE RESOURCES — Bootstrap (run once manually)
# Creates the DynamoDB table for Terraform state locking
# The S3 bucket (aws-terraform-state-bucket-0011) already exists
# ═══════════════════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "terraform-state-lock"
    Project     = "mdi-sovereign"
    ManagedBy   = "terraform"
    Purpose     = "Terraform state locking"
  }
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.terraform_lock.name
}
EOF

mkdir -p terraform/state-resources

echo ""
echo "=== Root Terraform Configuration Created ==="
echo ""
echo "  ✅ terraform/providers.tf"
echo "  ✅ terraform/backend.tf"
echo "  ✅ terraform/main.tf"
echo "  ✅ terraform/variables.tf"
echo "  ✅ terraform/outputs.tf"
echo "  ✅ terraform/state-resources/main.tf"
echo ""
echo "🎉 All 6 files created! Run 'git add . && git commit' to save."
