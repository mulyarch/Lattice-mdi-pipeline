# ═══════════════════════════════════════════════════════════════════════════════
# AZURE KEY VAULT — Secrets Management & Encryption
# Private endpoint access only, soft delete, purge protection
# ═══════════════════════════════════════════════════════════════════════════════

data "azurerm_client_config" "current" {}

# ─────────────────────────────────────────────
# KEY VAULT
# ─────────────────────────────────────────────

resource "azurerm_key_vault" "allied" {
  name                = "${var.project_name}-${var.environment}-kv"
  location            = azurerm_resource_group.allied.location
  resource_group_name = azurerm_resource_group.allied.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Security settings
  enabled_for_disk_encryption     = true
  enabled_for_deployment          = false
  enabled_for_template_deployment = false
  soft_delete_retention_days      = 90
  purge_protection_enabled        = true

  # CRITICAL: No public network access
  public_network_access_enabled = true

  # RBAC authorization (no access policies)
  enable_rbac_authorization = true

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"

    virtual_network_subnet_ids = [azurerm_subnet.aks_nodes.id]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-key-vault"
  }
}

# ─────────────────────────────────────────────
# PRIVATE ENDPOINT — Access Key Vault without internet
# ─────────────────────────────────────────────

resource "azurerm_private_endpoint" "key_vault" {
  name                = "${var.project_name}-${var.environment}-kv-pe"
  location            = azurerm_resource_group.allied.location
  resource_group_name = azurerm_resource_group.allied.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${var.project_name}-${var.environment}-kv-psc"
    private_connection_resource_id = azurerm_key_vault.allied.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "key-vault-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault.id]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-kv-private-endpoint"
  }
}

# Private DNS Zone for Key Vault
resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.allied.name

  tags = {
    Name = "${var.project_name}-${var.environment}-kv-dns-zone"
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                  = "${var.project_name}-${var.environment}-kv-dns-link"
  resource_group_name   = azurerm_resource_group.allied.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = azurerm_virtual_network.allied.id
}

# ─────────────────────────────────────────────
# ENCRYPTION KEY — For AKS disk encryption
# ─────────────────────────────────────────────

resource "azurerm_key_vault_key" "disk_encryption" {
  name         = "${var.project_name}-${var.environment}-disk-key"
  key_vault_id = azurerm_key_vault.allied.id
  key_type     = "RSA"
  key_size     = 4096

  key_opts = [
    "decrypt",
    "encrypt",
    "wrapKey",
    "unwrapKey"
  ]

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }
    expire_after         = "P365D"
    notify_before_expiry = "P30D"
  }

  depends_on = [
    azurerm_role_assignment.terraform_kv_admin
  ]
}

# ─────────────────────────────────────────────
# RBAC — Grant AKS access to Key Vault secrets
# ─────────────────────────────────────────────

resource "azurerm_role_assignment" "aks_kv_secrets" {
  scope                = azurerm_key_vault.allied.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.allied.key_vault_secrets_provider[0].secret_identity[0].object_id
}

# Grant Terraform identity admin access (for key creation)
resource "azurerm_role_assignment" "terraform_kv_admin" {
  scope                = azurerm_key_vault.allied.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}
