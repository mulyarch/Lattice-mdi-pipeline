# ═══════════════════════════════════════════════════════════════════════════════
# CROSS-CLOUD VPN MODULE — AWS ↔ Azure Site-to-Site IPsec
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_vpn_gateway" "sovereign" {
  vpc_id          = var.aws_vpc_id
  amazon_side_asn = var.aws_bgp_asn

  tags = {
    Name        = "${var.project_name}-${var.environment}-vpn-gw"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_vpn_gateway_route_propagation" "private" {
  vpn_gateway_id = aws_vpn_gateway.sovereign.id
  route_table_id = var.aws_private_route_table_id
}

resource "aws_vpn_gateway_route_propagation" "intra" {
  vpn_gateway_id = aws_vpn_gateway.sovereign.id
  route_table_id = var.aws_intra_route_table_id
}

resource "aws_customer_gateway" "azure" {
  bgp_asn    = var.azure_bgp_asn
  ip_address = azurerm_public_ip.vpn_gateway.ip_address
  type       = "ipsec.1"

  tags = {
    Name        = "${var.project_name}-${var.environment}-azure-cgw"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_vpn_connection" "to_azure" {
  vpn_gateway_id      = aws_vpn_gateway.sovereign.id
  customer_gateway_id = aws_customer_gateway.azure.id
  type                = "ipsec.1"
  static_routes_only  = false

  tunnel1_preshared_key = var.vpn_preshared_key_tunnel1
  tunnel2_preshared_key = var.vpn_preshared_key_tunnel2

  tunnel1_ike_versions                 = ["ikev2"]
  tunnel1_phase1_encryption_algorithms = ["AES256"]
  tunnel1_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase1_dh_group_numbers      = [14]
  tunnel1_phase1_lifetime_seconds      = 28800
  tunnel1_phase2_encryption_algorithms = ["AES256"]
  tunnel1_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase2_dh_group_numbers      = [14]
  tunnel1_phase2_lifetime_seconds      = 3600

  tunnel2_ike_versions                 = ["ikev2"]
  tunnel2_phase1_encryption_algorithms = ["AES256"]
  tunnel2_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase1_dh_group_numbers      = [14]
  tunnel2_phase1_lifetime_seconds      = 28800
  tunnel2_phase2_encryption_algorithms = ["AES256"]
  tunnel2_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase2_dh_group_numbers      = [14]
  tunnel2_phase2_lifetime_seconds      = 3600

  tags = {
    Name        = "${var.project_name}-${var.environment}-vpn-to-azure"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "azurerm_public_ip" "vpn_gateway" {
  name                = "${var.project_name}-${var.environment}-vpn-gw-pip"
  location            = var.azure_region
  resource_group_name = var.azure_resource_group_name
  allocation_method   = "Static"
  zones               = ["1", "2", "3"]
  sku                 = "Standard"

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "azurerm_virtual_network_gateway" "allied" {
  name                = "${var.project_name}-${var.environment}-vpn-gw"
  location            = var.azure_region
  resource_group_name = var.azure_resource_group_name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw1AZ"
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
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "azurerm_local_network_gateway" "aws_tunnel1" {
  name                = "${var.project_name}-${var.environment}-aws-lng-t1"
  location            = var.azure_region
  resource_group_name = var.azure_resource_group_name
  gateway_address     = aws_vpn_connection.to_azure.tunnel1_address
  address_space       = [var.aws_vpc_cidr]

  bgp_settings {
    asn                 = var.aws_bgp_asn
    bgp_peering_address = aws_vpn_connection.to_azure.tunnel1_bgp_asn
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Tunnel      = "1"
  }
}

resource "azurerm_local_network_gateway" "aws_tunnel2" {
  name                = "${var.project_name}-${var.environment}-aws-lng-t2"
  location            = var.azure_region
  resource_group_name = var.azure_resource_group_name
  gateway_address     = aws_vpn_connection.to_azure.tunnel2_address
  address_space       = [var.aws_vpc_cidr]

  bgp_settings {
    asn                 = var.aws_bgp_asn
    bgp_peering_address = aws_vpn_connection.to_azure.tunnel2_bgp_asn
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Tunnel      = "2"
  }
}

resource "azurerm_virtual_network_gateway_connection" "to_aws_tunnel1" {
  name                       = "${var.project_name}-${var.environment}-to-aws-t1"
  location                   = var.azure_region
  resource_group_name        = var.azure_resource_group_name
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.allied.id
  local_network_gateway_id   = azurerm_local_network_gateway.aws_tunnel1.id
  shared_key                 = var.vpn_preshared_key_tunnel1
  enable_bgp                 = true

  ipsec_policy {
    ike_encryption   = "AES256"
    ike_integrity    = "SHA256"
    dh_group         = "DHGroup14"
    ipsec_encryption = "AES256"
    ipsec_integrity  = "SHA256"
    pfs_group        = "PFS14"
    sa_lifetime      = 3600
    sa_datasize      = 1024
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Tunnel      = "1"
  }
}

resource "azurerm_virtual_network_gateway_connection" "to_aws_tunnel2" {
  name                       = "${var.project_name}-${var.environment}-to-aws-t2"
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
    sa_datasize      = 1024
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Tunnel      = "2"
  }
}

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
    VpnId           = aws_vpn_connection.to_azure.id
    TunnelIpAddress = aws_vpn_connection.to_azure.tunnel1_address
  }

  alarm_actions = [var.aws_sns_topic_arn]
  ok_actions    = [var.aws_sns_topic_arn]

  tags = {
    Project     = var.project_name
    Environment = var.environment
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
    VpnId           = aws_vpn_connection.to_azure.id
    TunnelIpAddress = aws_vpn_connection.to_azure.tunnel2_address
  }

  alarm_actions = [var.aws_sns_topic_arn]
  ok_actions    = [var.aws_sns_topic_arn]

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

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
