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
