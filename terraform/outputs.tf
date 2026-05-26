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
