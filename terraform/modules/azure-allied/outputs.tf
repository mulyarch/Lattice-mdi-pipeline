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
