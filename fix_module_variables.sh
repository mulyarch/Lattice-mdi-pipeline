#!/bin/bash
# Run from the root of your anduril-mdi-pipeline directory
# This adds the missing variables.tf and outputs.tf to each module

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 1: terraform/modules/aws-sovereign/variables.tf
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

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 2: terraform/modules/aws-sovereign/outputs.tf
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/modules/aws-sovereign/outputs.tf << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# AWS SOVEREIGN MODULE — Outputs
# ═══════════════════════════════════════════════════════════════════════════════

output "vpc_id" {
  description = "ID of the sovereign VPC"
  value       = aws_vpc.sovereign.id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "intra_subnet_ids" {
  description = "IDs of intra subnets"
  value       = aws_subnet.intra[*].id
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = aws_route_table.private.id
}

output "intra_route_table_id" {
  description = "ID of the intra route table"
  value       = aws_route_table.intra.id
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.sovereign.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.sovereign.endpoint
}

output "eks_cluster_ca_certificate" {
  description = "EKS cluster CA certificate"
  value       = aws_eks_cluster.sovereign.certificate_authority[0].data
}

output "eks_cluster_version" {
  description = "EKS cluster Kubernetes version"
  value       = aws_eks_cluster.sovereign.version
}

output "s3_bucket_name" {
  description = "Name of the mission data S3 bucket"
  value       = aws_s3_bucket.mission_data.id
}

output "s3_bucket_arn" {
  description = "ARN of the mission data S3 bucket"
  value       = aws_s3_bucket.mission_data.arn
}

output "kms_key_arn" {
  description = "ARN of the sovereign KMS key"
  value       = aws_kms_key.sovereign.arn
}

output "kms_key_id" {
  description = "ID of the sovereign KMS key"
  value       = aws_kms_key.sovereign.id
}

output "sns_topic_arn" {
  description = "ARN of the security alerts SNS topic"
  value       = aws_sns_topic.security_alerts.arn
}

output "eks_node_role_arn" {
  description = "ARN of the EKS node IAM role"
  value       = aws_iam_role.eks_nodes.arn
}
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 3: terraform/modules/azure-allied/variables.tf
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
  description = "Kubernetes version for AKS"
  type        = string
  default     = "1.29"
}

variable "aks_node_vm_size" {
  description = "VM size for AKS nodes"
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

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 4: terraform/modules/azure-allied/outputs.tf
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
  value       = azurerm_subnet.aks.id
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
# FILE 5: terraform/modules/cross-cloud-vpn/variables.tf
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/modules/cross-cloud-vpn/variables.tf << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# CROSS-CLOUD VPN MODULE — Input Variables
# ═══════════════════════════════════════════════════════════════════════════════

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

# ─── AWS Side ───

variable "aws_vpc_id" {
  description = "ID of the AWS VPC"
  type        = string
}

variable "aws_vpc_cidr" {
  description = "CIDR of the AWS VPC"
  type        = string
}

variable "aws_private_route_table_id" {
  description = "ID of the AWS private route table"
  type        = string
}

variable "aws_intra_route_table_id" {
  description = "ID of the AWS intra route table"
  type        = string
}

variable "aws_bgp_asn" {
  description = "BGP ASN for AWS VPN Gateway"
  type        = number
  default     = 64512
}

variable "aws_sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  type        = string
}

# ─── Azure Side ───

variable "azure_region" {
  description = "Azure region"
  type        = string
}

variable "azure_resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
}

variable "azure_gateway_subnet_id" {
  description = "ID of the Azure GatewaySubnet"
  type        = string
}

variable "azure_vnet_cidr" {
  description = "CIDR of the Azure VNet"
  type        = string
}

variable "azure_bgp_asn" {
  description = "BGP ASN for Azure VPN Gateway"
  type        = number
  default     = 65515
}

variable "azure_log_analytics_workspace_id" {
  description = "ID of the Azure Log Analytics workspace"
  type        = string
}

# ─── VPN Secrets ───

variable "vpn_preshared_key_tunnel1" {
  description = "Pre-shared key for VPN tunnel 1"
  type        = string
  sensitive   = true
}

variable "vpn_preshared_key_tunnel2" {
  description = "Pre-shared key for VPN tunnel 2"
  type        = string
  sensitive   = true
}
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 6: terraform/modules/cross-cloud-vpn/outputs.tf
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/modules/cross-cloud-vpn/outputs.tf << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# CROSS-CLOUD VPN MODULE — Outputs
# ═══════════════════════════════════════════════════════════════════════════════

output "aws_vpn_gateway_id" {
  description = "ID of the AWS VPN Gateway"
  value       = aws_vpn_gateway.sovereign.id
}

output "aws_vpn_connection_id" {
  description = "ID of the AWS VPN Connection"
  value       = aws_vpn_connection.to_azure.id
}

output "azure_vpn_gateway_public_ip" {
  description = "Public IP of the Azure VPN Gateway"
  value       = azurerm_public_ip.vpn_gateway.ip_address
}

output "vpn_tunnel_status" {
  description = "VPN tunnel configuration summary"
  value = {
    aws_vpn_gateway_id = aws_vpn_gateway.sovereign.id
    azure_gateway_ip   = azurerm_public_ip.vpn_gateway.ip_address
    encryption         = "AES-256 / IKEv2"
    routing            = "BGP"
    aws_bgp_asn        = var.aws_bgp_asn
    azure_bgp_asn      = var.azure_bgp_asn
    tunnels            = 2
  }
}
EOF

echo ""
echo "=== Module Variables & Outputs Fixed ==="
echo ""
echo "  ✅ terraform/modules/aws-sovereign/variables.tf"
echo "  ✅ terraform/modules/aws-sovereign/outputs.tf"
echo "  ✅ terraform/modules/azure-allied/variables.tf"
echo "  ✅ terraform/modules/azure-allied/outputs.tf"
echo "  ✅ terraform/modules/cross-cloud-vpn/variables.tf"
echo "  ✅ terraform/modules/cross-cloud-vpn/outputs.tf"
echo ""
echo "Now run: cd terraform && terraform init -backend=false && terraform validate"
