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
