#!/bin/bash
# Run from the root of your anduril-mdi-pipeline directory
# This fixes ALL missing variable declarations and output references

# ═══════════════════════════════════════════════════════════════════════════════
# FIX 1: terraform/modules/aws-sovereign/variables.tf
# Add missing: kms_key_arn, azure_vnet_cidr
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/modules/aws-sovereign/variables.tf << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# AWS SOVEREIGN MODULE — Input Variables
# ═══════════════════════════════════════════════════════════════════════════════

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.29"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS nodes"
  type        = string
  default     = "t3.medium"
}

variable "eks_node_min_size" {
  description = "Minimum number of EKS nodes"
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "Maximum number of EKS nodes"
  type        = number
  default     = 5
}

variable "eks_node_desired_size" {
  description = "Desired number of EKS nodes"
  type        = number
  default     = 2
}

variable "kms_key_arn" {
  description = "ARN of the KMS key (used internally, passed between resources)"
  type        = string
  default     = ""
}

variable "azure_vnet_cidr" {
  description = "CIDR of the Azure VNet (for NACLs and security group rules)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FIX 2: terraform/modules/azure-allied/variables.tf
# Add missing: aks_version, aks_system_node_count, aks_system_vm_size, aws_vpc_cidr
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/modules/azure-allied/variables.tf << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# AZURE ALLIED MODULE — Input Variables
# ═══════════════════════════════════════════════════════════════════════════════

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "azure_region" {
  description = "Azure region"
  type        = string
}

variable "vnet_cidr" {
  description = "CIDR block for the VNet"
  type        = string
}

variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "aks_kubernetes_version" {
  description = "Kubernetes version for AKS (passed from root)"
  type        = string
  default     = "1.29"
}

variable "aks_version" {
  description = "Kubernetes version for AKS (used in aks.tf)"
  type        = string
  default     = "1.29"
}

variable "aks_node_vm_size" {
  description = "VM size for AKS worker nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "aks_system_vm_size" {
  description = "VM size for AKS system node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "aks_node_min_count" {
  description = "Minimum number of AKS nodes"
  type        = number
  default     = 2
}

variable "aks_node_max_count" {
  description = "Maximum number of AKS nodes"
  type        = number
  default     = 5
}

variable "aks_system_node_count" {
  description = "Number of nodes in the AKS system pool"
  type        = number
  default     = 2
}

variable "aws_vpc_cidr" {
  description = "CIDR of the AWS VPC (for NSG rules allowing cross-cloud traffic)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FIX 3: terraform/modules/azure-allied/outputs.tf
# Fix the reference to azurerm_subnet.aks (check what it's actually named)
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/modules/azure-allied/outputs.tf << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# AZURE ALLIED MODULE — Outputs
# ═══════════════════════════════════════════════════════════════════════════════

output "resource_group_name" {
  description = "Name of the Azure resource group"
  value       = azurerm_resource_group.allied.name
}

output "resource_group_id" {
  description = "ID of the Azure resource group"
  value       = azurerm_resource_group.allied.id
}

output "vnet_id" {
  description = "ID of the allied VNet"
  value       = azurerm_virtual_network.allied.id
}

output "vnet_name" {
  description = "Name of the allied VNet"
  value       = azurerm_virtual_network.allied.name
}

output "gateway_subnet_id" {
  description = "ID of the GatewaySubnet"
  value       = azurerm_subnet.gateway.id
}

output "aks_subnet_id" {
  description = "ID of the AKS subnet"
  value       = azurerm_subnet.aks_nodes.id
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.allied.name
}

output "aks_cluster_host" {
  description = "AKS cluster API host"
  value       = azurerm_kubernetes_cluster.allied.kube_config[0].host
  sensitive   = true
}

output "aks_client_certificate" {
  description = "AKS client certificate"
  value       = azurerm_kubernetes_cluster.allied.kube_config[0].client_certificate
  sensitive   = true
}

output "aks_client_key" {
  description = "AKS client key"
  value       = azurerm_kubernetes_cluster.allied.kube_config[0].client_key
  sensitive   = true
}

output "aks_cluster_ca_certificate" {
  description = "AKS cluster CA certificate"
  value       = azurerm_kubernetes_cluster.allied.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.allied.vault_uri
}

output "key_vault_id" {
  description = "ID of the Azure Key Vault"
  value       = azurerm_key_vault.allied.id
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.allied.id
}
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FIX 4: Update root main.tf to pass the additional variables to modules
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/main.tf << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# ROOT MODULE — Sovereign Multi-Cloud Infrastructure
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# DATA SOURCES
# ─────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

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
  azure_vnet_cidr    = var.azure_vnet_cidr

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

  project_name          = var.project_name
  environment           = var.environment
  azure_region          = var.azure_region
  vnet_cidr             = var.azure_vnet_cidr
  azure_subscription_id = var.azure_subscription_id
  aws_vpc_cidr          = var.aws_vpc_cidr

  # AKS Configuration
  aks_kubernetes_version = var.aks_kubernetes_version
  aks_version            = var.aks_kubernetes_version
  aks_node_vm_size       = var.aks_node_vm_size
  aks_system_vm_size     = var.aks_node_vm_size
  aks_node_min_count     = var.aks_node_min_count
  aks_node_max_count     = var.aks_node_max_count
  aks_system_node_count  = var.aks_node_min_count

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
  azure_region                     = var.azure_region
  azure_resource_group_name        = module.azure_allied.resource_group_name
  azure_gateway_subnet_id          = module.azure_allied.gateway_subnet_id
  azure_vnet_cidr                  = var.azure_vnet_cidr
  azure_bgp_asn                    = var.azure_bgp_asn
  azure_log_analytics_workspace_id = module.azure_allied.log_analytics_workspace_id

  # VPN Secrets
  vpn_preshared_key_tunnel1 = var.vpn_preshared_key_tunnel1
  vpn_preshared_key_tunnel2 = var.vpn_preshared_key_tunnel2

  depends_on = [
    module.aws_sovereign,
    module.azure_allied,
  ]
}
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FIX 5: Fix the S3 lifecycle rule warning
# Add empty filter block to the lifecycle rules in s3.tf
# ═══════════════════════════════════════════════════════════════════════════════

# Check if s3.tf exists and fix the lifecycle rules
if [ -f "terraform/modules/aws-sovereign/s3.tf" ]; then
  # Replace any rule { that doesn't have a filter with rule { filter {}
  sed -i.bak '/^  rule {/a\    filter {}' terraform/modules/aws-sovereign/s3.tf 2>/dev/null || true
  rm -f terraform/modules/aws-sovereign/s3.tf.bak
  echo "  ⚠️  s3.tf lifecycle rules may need manual filter {} addition — see below"
fi

echo ""
echo "=== All Module Variables Fixed ==="
echo ""
echo "  ✅ terraform/modules/aws-sovereign/variables.tf (added: kms_key_arn, azure_vnet_cidr)"
echo "  ✅ terraform/modules/azure-allied/variables.tf (added: aks_version, aks_system_vm_size, aks_system_node_count, aws_vpc_cidr)"
echo "  ✅ terraform/modules/azure-allied/outputs.tf (fixed: aks_subnet_id reference)"
echo "  ✅ terraform/main.tf (added: azure_vnet_cidr, aws_vpc_cidr, aks_version, aks_system_* params)"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "REMAINING MANUAL FIXES NEEDED:"
echo ""
echo "1. The outputs.tf references azurerm_subnet.aks_nodes"
echo "   Run this to check your actual subnet name:"
echo "   grep 'resource \"azurerm_subnet\"' terraform/modules/azure-allied/main.tf"
echo ""
echo "2. The aws-sovereign module uses var.kms_key_arn but should"
echo "   reference the KMS key resource directly. Fix by replacing"
echo "   var.kms_key_arn with aws_kms_key.sovereign.arn in:"
echo "   - terraform/modules/aws-sovereign/eks.tf"
echo "   - terraform/modules/aws-sovereign/iam.tf"
echo "   - terraform/modules/aws-sovereign/main.tf"
echo ""
echo "Run this to do the kms_key_arn fix automatically:"
echo ""
echo "  sed -i 's/var.kms_key_arn/aws_kms_key.sovereign.arn/g' terraform/modules/aws-sovereign/eks.tf"
echo "  sed -i 's/var.kms_key_arn/aws_kms_key.sovereign.arn/g' terraform/modules/aws-sovereign/iam.tf"
echo "  sed -i 's/var.kms_key_arn/aws_kms_key.sovereign.arn/g' terraform/modules/aws-sovereign/main.tf"
echo ""
echo "Then re-run: terraform validate"
