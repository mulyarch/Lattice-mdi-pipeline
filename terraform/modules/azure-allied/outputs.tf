# ─────────────────────────────────────────────
# Azure Allied Module Outputs
# ─────────────────────────────────────────────

# Networking
output "vnet_id" {
  description = "ID of the allied VNet"
  value       = azurerm_virtual_network.allied.id
}

output "vnet_name" {
  description = "Name of the allied VNet"
  value       = azurerm_virtual_network.allied.name
}

output "vnet_cidr" {
  description = "CIDR block of the allied VNet"
  value       = azurerm_virtual_network.allied.address_space[0]
}

output "gateway_subnet_id" {
  description = "ID of the gateway subnet (for VPN)"
  value       = azurerm_subnet.gateway.id
}

output "aks_subnet_id" {
  description = "ID of the AKS nodes subnet"
  value       = azurerm_subnet.aks_nodes.id
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.allied.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.allied.location
}

# AKS
output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.allied.name
}

output "aks_cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.allied.id
}

output "aks_kube_config" {
  description = "AKS kubeconfig (sensitive)"
  value       = azurerm_kubernetes_cluster.allied.kube_config_raw
  sensitive   = true
}

# Key Vault
output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.allied.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.allied.vault_uri
}

# Storage
output "storage_account_name" {
  description = "Name of the mission data storage account"
  value       = azurerm_storage_account.mission_data.name
}

output "storage_account_id" {
  description = "ID of the mission data storage account"
  value       = azurerm_storage_account.mission_data.id
}

# Monitoring
output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.allied.id
}
