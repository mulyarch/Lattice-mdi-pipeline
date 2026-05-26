
#!/bin/bash
# Run from the root of your anduril-mdi-pipeline directory
# This creates the cross-cloud VPN module files

# Remove the placeholder .gitkeep
rm -f terraform/modules/cross-cloud-vpn/.gitkeep

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 1: terraform/modules/cross-cloud-vpn/main.tf
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/modules/cross-cloud-vpn/main.tf << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# CROSS-CLOUD VPN MODULE
# Site-to-Site IPsec VPN connecting AWS Sovereign VPC ↔ Azure Allied VNet
# Simulates encrypted multinational defense network (AUKUS-style connectivity)
#
# Architecture:
#   AWS VPN Gateway ←── IPsec Tunnel (AES-256, SHA-256) ──→ Azure VPN Gateway
#
# This enables:
#   - Secure data flow between sovereign environments
#   - Cross-cloud Kubernetes pod communication
#   - Edge-to-cloud telemetry routing across allied networks
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# AWS SIDE — Virtual Private Gateway + VPN Connection
# ─────────────────────────────────────────────

# Virtual Private Gateway (attached to sovereign VPC)
resource "aws_vpn_gateway" "sovereign" {
  vpc_id          = var.aws_vpc_id
  amazon_side_asn = var.aws_bgp_asn

  tags = {
    Name = "${var.project_name}-${var.environment}-vpn-gateway"
  }
}

# Enable route propagation to private subnets
resource "aws_vpn_gateway_route_propagation" "private" {
  vpn_gateway_id = aws_vpn_gateway.sovereign.id
  route_table_id = var.aws_private_route_table_id
}

resource "aws_vpn_gateway_route_propagation" "intra" {
  vpn_gateway_id = aws_vpn_gateway.sovereign.id
  route_table_id = var.aws_intra_route_table_id
}

# Customer Gateway (represents the Azure VPN Gateway from AWS's perspective)
resource "aws_customer_gateway" "azure" {
  bgp_asn    = var.azure_bgp_asn
  ip_address = azurerm_public_ip.vpn_gateway.ip_address
  type       = "ipsec.1"

  tags = {
    Name = "${var.project_name}-${var.environment}-azure-cgw"
  }
}

# Site-to-Site VPN Connection (AWS → Azure)
resource "aws_vpn_connection" "to_azure" {
  vpn_gateway_id      = aws_vpn_gateway.sovereign.id
  customer_gateway_id = aws_customer_gateway.azure.id
  type                = "ipsec.1"
  static_routes_only  = false  # Use BGP for dynamic routing

  # Tunnel 1 Configuration — Strong encryption
  tunnel1_ike_versions                 = ["ikev2"]
  tunnel1_phase1_dh_group_numbers      = [14]       # 2048-bit MODP
  tunnel1_phase1_encryption_algorithms = ["AES256"]
  tunnel1_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase1_lifetime_seconds      = 28800      # 8 hours

  tunnel1_phase2_dh_group_numbers      = [14]
  tunnel1_phase2_encryption_algorithms = ["AES256"]
  tunnel1_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase2_lifetime_seconds      = 3600       # 1 hour

  tunnel1_preshared_key = var.vpn_preshared_key_tunnel1

  # Tunnel 2 Configuration — Redundancy
  tunnel2_ike_versions                 = ["ikev2"]
  tunnel2_phase1_dh_group_numbers      = [14]
  tunnel2_phase1_encryption_algorithms = ["AES256"]
  tunnel2_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase1_lifetime_seconds      = 28800

  tunnel2_phase2_dh_group_numbers      = [14]
  tunnel2_phase2_encryption_algorithms = ["AES256"]
  tunnel2_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase2_lifetime_seconds      = 3600

  tunnel2_preshared_key = var.vpn_preshared_key_tunnel2

  tags = {
    Name = "${var.project_name}-${var.environment}-vpn-to-azure"
  }
}

# ─────────────────────────────────────────────
# AZURE SIDE — VPN Gateway + Connection
# ─────────────────────────────────────────────

# Public IP for Azure VPN Gateway
resource "azurerm_public_ip" "vpn_gateway" {
  name                = "${var.project_name}-${var.environment}-vpn-gw-pip"
  location            = var.azure_region
  resource_group_name = var.azure_resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    Name = "${var.project_name}-${var.environment}-vpn-gateway-ip"
  }
}

# Azure VPN Gateway
resource "azurerm_virtual_network_gateway" "allied" {
  name                = "${var.project_name}-${var.environment}-vpn-gateway"
  location            = var.azure_region
  resource_group_name = var.azure_resource_group_name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw2"  # Supports BGP + high throughput
  active_active       = false
  enable_bgp          = true

  bgp_settings {
    asn = var.azure_bgp_asn
  }

  ip_configuration {
    name                          = "vpn-gateway-config"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = var.azure_gateway_subnet_id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-vpn-gateway"
  }
}

# Local Network Gateway (represents AWS VPN from Azure's perspective)
# Tunnel 1
resource "azurerm_local_network_gateway" "aws_tunnel1" {
  name                = "${var.project_name}-${var.environment}-aws-lng-tunnel1"
  location            = var.azure_region
  resource_group_name = var.azure_resource_group_name
  gateway_address     = aws_vpn_connection.to_azure.tunnel1_address

  bgp_settings {
    asn                 = var.aws_bgp_asn
    bgp_peering_address = aws_vpn_connection.to_azure.tunnel1_bgp_asn
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-aws-tunnel1"
  }
}

# Tunnel 2 (redundancy)
resource "azurerm_local_network_gateway" "aws_tunnel2" {
  name                = "${var.project_name}-${var.environment}-aws-lng-tunnel2"
  location            = var.azure_region
  resource_group_name = var.azure_resource_group_name
  gateway_address     = aws_vpn_connection.to_azure.tunnel2_address

  bgp_settings {
    asn                 = var.aws_bgp_asn
    bgp_peering_address = aws_vpn_connection.to_azure.tunnel2_bgp_asn
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-aws-tunnel2"
  }
}

# VPN Connection — Tunnel 1
resource "azurerm_virtual_network_gateway_connection" "to_aws_tunnel1" {
  name                       = "${var.project_name}-${var.environment}-to-aws-tunnel1"
  location                   = var.azure_region
  resource_group_name        = var.azure_resource_group_name
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.allied.id
  local_network_gateway_id   = azurerm_local_network_gateway.aws_tunnel1.id
  shared_key                 = var.vpn_preshared_key_tunnel1
  enable_bgp                 = true

  # Match AWS tunnel encryption settings
  ipsec_policy {
    ike_encryption   = "AES256"
    ike_integrity    = "SHA256"
    dh_group         = "DHGroup14"
    ipsec_encryption = "AES256"
    ipsec_integrity  = "SHA256"
    pfs_group        = "PFS14"
    sa_lifetime      = 3600
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-vpn-to-aws-tunnel1"
  }
}

# VPN Connection — Tunnel 2 (redundancy)
resource "azurerm_virtual_network_gateway_connection" "to_aws_tunnel2" {
  name                       = "${var.project_name}-${var.environment}-to-aws-tunnel2"
  location                   = var.azure_region
  resource_group_name        = var.azure_resource_group_name
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.allied.id
  local_network_gateway_id   = azurerm_local_network_gateway.aws_tunnel2.id
  shared_key                 = var.vpn_preshared_key_tunnel2
  enable_bgp                 = true

  ipsec_policy {
    ike_encryption   = "AES256"
    ike_integrity    = "SHA256"
    dh_group         = "DHGroup14"
    ipsec_encryption = "AES256"
    ipsec_integrity  = "SHA256"
    pfs_group        = "PFS14"
    sa_lifetime      = 3600
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-vpn-to-aws-tunnel2"
  }
}

# ─────────────────────────────────────────────
# CLOUDWATCH MONITORING — VPN Tunnel Health
# ─────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "vpn_tunnel1_down" {
  alarm_name          = "${var.project_name}-${var.environment}-vpn-tunnel1-down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TunnelState"
  namespace           = "AWS/VPN"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "VPN Tunnel 1 to Azure is DOWN"
  treat_missing_data  = "breaching"

  dimensions = {
    VpnId    = aws_vpn_connection.to_azure.id
    TunnelIpAddress = aws_vpn_connection.to_azure.tunnel1_address
  }

  alarm_actions = var.aws_sns_topic_arn != "" ? [var.aws_sns_topic_arn] : []

  tags = {
    Name = "${var.project_name}-${var.environment}-vpn-tunnel1-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "vpn_tunnel2_down" {
  alarm_name          = "${var.project_name}-${var.environment}-vpn-tunnel2-down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TunnelState"
  namespace           = "AWS/VPN"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "VPN Tunnel 2 to Azure is DOWN"
  treat_missing_data  = "breaching"

  dimensions = {
    VpnId    = aws_vpn_connection.to_azure.id
    TunnelIpAddress = aws_vpn_connection.to_azure.tunnel2_address
  }

  alarm_actions = var.aws_sns_topic_arn != "" ? [var.aws_sns_topic_arn] : []

  tags = {
    Name = "${var.project_name}-${var.environment}-vpn-tunnel2-alarm"
  }
}

# ─────────────────────────────────────────────
# AZURE MONITORING — Connection Health
# ─────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "vpn_gateway" {
  name                       = "${var.project_name}-${var.environment}-vpn-diag"
  target_resource_id         = azurerm_virtual_network_gateway.allied.id
  log_analytics_workspace_id = var.azure_log_analytics_workspace_id

  enabled_log {
    category = "GatewayDiagnosticLog"
  }

  enabled_log {
    category = "TunnelDiagnosticLog"
  }

  enabled_log {
    category = "RouteDiagnosticLog"
  }

  enabled_log {
    category = "IKEDiagnosticLog"
  }

  metric {
    category = "AllMetrics"
  }
}
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 2: terraform/modules/cross-cloud-vpn/variables.tf
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/modules/cross-cloud-vpn/variables.tf << 'EOF'
# ─────────────────────────────────────────────
# Cross-Cloud VPN Module Variables
# ─────────────────────────────────────────────

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

# ─────────────────────────────────────────────
# AWS Variables
# ─────────────────────────────────────────────

variable "aws_vpc_id" {
  description = "ID of the AWS sovereign VPC"
  type        = string
}

variable "aws_vpc_cidr" {
  description = "CIDR of the AWS sovereign VPC"
  type        = string
}

variable "aws_private_route_table_id" {
  description = "Route table ID for AWS private subnets"
  type        = string
}

variable "aws_intra_route_table_id" {
  description = "Route table ID for AWS intra subnets"
  type        = string
}

variable "aws_bgp_asn" {
  description = "BGP ASN for AWS side"
  type        = number
  default     = 64512
}

variable "aws_sns_topic_arn" {
  description = "SNS topic ARN for VPN alerts (optional)"
  type        = string
  default     = ""
}

# ─────────────────────────────────────────────
# Azure Variables
# ─────────────────────────────────────────────

variable "azure_region" {
  description = "Azure region for VPN gateway"
  type        = string
}

variable "azure_resource_group_name" {
  description = "Azure resource group name"
  type        = string
}

variable "azure_gateway_subnet_id" {
  description = "ID of the Azure GatewaySubnet"
  type        = string
}

variable "azure_vnet_cidr" {
  description = "CIDR of the Azure allied VNet"
  type        = string
}

variable "azure_bgp_asn" {
  description = "BGP ASN for Azure side"
  type        = number
  default     = 65515
}

variable "azure_log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for VPN diagnostics"
  type        = string
}

# ─────────────────────────────────────────────
# VPN Tunnel Secrets
# ─────────────────────────────────────────────

variable "vpn_preshared_key_tunnel1" {
  description = "Pre-shared key for VPN tunnel 1 (min 32 chars)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.vpn_preshared_key_tunnel1) >= 32
    error_message = "Pre-shared key must be at least 32 characters for security."
  }
}

variable "vpn_preshared_key_tunnel2" {
  description = "Pre-shared key for VPN tunnel 2 (min 32 chars)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.vpn_preshared_key_tunnel2) >= 32
    error_message = "Pre-shared key must be at least 32 characters for security."
  }
}
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 3: terraform/modules/cross-cloud-vpn/outputs.tf
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/modules/cross-cloud-vpn/outputs.tf << 'EOF'
# ─────────────────────────────────────────────
# Cross-Cloud VPN Module Outputs
# ─────────────────────────────────────────────

# AWS Outputs
output "aws_vpn_gateway_id" {
  description = "ID of the AWS VPN Gateway"
  value       = aws_vpn_gateway.sovereign.id
}

output "aws_vpn_connection_id" {
  description = "ID of the AWS VPN connection"
  value       = aws_vpn_connection.to_azure.id
}

output "aws_tunnel1_address" {
  description = "Public IP of AWS VPN tunnel 1"
  value       = aws_vpn_connection.to_azure.tunnel1_address
}

output "aws_tunnel2_address" {
  description = "Public IP of AWS VPN tunnel 2"
  value       = aws_vpn_connection.to_azure.tunnel2_address
}

output "aws_tunnel1_bgp_asn" {
  description = "BGP ASN for tunnel 1"
  value       = aws_vpn_connection.to_azure.tunnel1_bgp_asn
}

output "aws_tunnel2_bgp_asn" {
  description = "BGP ASN for tunnel 2"
  value       = aws_vpn_connection.to_azure.tunnel2_bgp_asn
}

# Azure Outputs
output "azure_vpn_gateway_id" {
  description = "ID of the Azure VPN Gateway"
  value       = azurerm_virtual_network_gateway.allied.id
}

output "azure_vpn_gateway_public_ip" {
  description = "Public IP of the Azure VPN Gateway"
  value       = azurerm_public_ip.vpn_gateway.ip_address
}

output "azure_vpn_connection_tunnel1_id" {
  description = "ID of Azure VPN connection (tunnel 1)"
  value       = azurerm_virtual_network_gateway_connection.to_aws_tunnel1.id
}

output "azure_vpn_connection_tunnel2_id" {
  description = "ID of Azure VPN connection (tunnel 2)"
  value       = azurerm_virtual_network_gateway_connection.to_aws_tunnel2.id
}

# Connection Status
output "vpn_tunnel_status" {
  description = "Summary of VPN tunnel configuration"
  value = {
    aws_vpn_gateway_id    = aws_vpn_gateway.sovereign.id
    azure_vpn_gateway_id  = azurerm_virtual_network_gateway.allied.id
    encryption            = "AES-256"
    integrity             = "SHA2-256"
    dh_group              = "Group14 (2048-bit)"
    ike_version           = "IKEv2"
    routing               = "BGP"
    redundancy            = "Dual tunnel (active/passive)"
  }
}
EOF

echo ""
echo "=== Cross-Cloud VPN Module Created ==="
echo ""
echo "  ✅ terraform/modules/cross-cloud-vpn/main.tf"
echo "  ✅ terraform/modules/cross-cloud-vpn/variables.tf"
echo "  ✅ terraform/modules/cross-cloud-vpn/outputs.tf"
echo ""
echo "🎉 All 3 files created! Run 'git add . && git commit' to save."

