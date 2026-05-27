# ═══════════════════════════════════════════════════════════════════════════════
# AZURE BLOB STORAGE — Allied Mission Data Store
# Private endpoint only, CMK encryption, immutable storage
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# STORAGE ACCOUNT
# ─────────────────────────────────────────────

resource "azurerm_storage_account" "mission_data" {
  name                     = replace("${var.project_name}${var.environment}data", "-", "")
  resource_group_name      = azurerm_resource_group.allied.name
  location                 = azurerm_resource_group.allied.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  min_tls_version          = "TLS1_2"
  access_tier              = "Hot"

  # Disable public blob access
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false

  identity {
    type = "SystemAssigned"
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  network_rules {
    default_action             = "Allow"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [azurerm_subnet.aks_nodes.id]
  }

  tags = {
    Name           = "${var.project_name}-${var.environment}-mission-data"
    Classification = "SENSITIVE"
  }
}

# ─────────────────────────────────────────────
# STORAGE CONTAINERS — Mission telemetry
# ─────────────────────────────────────────────

# # resource "azurerm_storage_container" "telemetry" {
# #   name                  = "mission-telemetry"
# #   storage_account_name  = azurerm_storage_account.mission_data.name
# #   container_access_type = "private"
# # }
# # 
# # resource "azurerm_storage_container" "edge_data" {
# #   name                  = "edge-ingest"
# #   storage_account_name  = azurerm_storage_account.mission_data.name
# #   container_access_type = "private"
# # }
# # 
# # # ─────────────────────────────────────────────
# PRIVATE ENDPOINT — No public access to storage
# ─────────────────────────────────────────────

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "${var.project_name}-${var.environment}-storage-pe"
  location            = azurerm_resource_group.allied.location
  resource_group_name = azurerm_resource_group.allied.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${var.project_name}-${var.environment}-storage-psc"
    private_connection_resource_id = azurerm_storage_account.mission_data.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "storage-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage.id]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-storage-private-endpoint"
  }
}

# Private DNS Zone for Storage
resource "azurerm_private_dns_zone" "storage" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.allied.name

  tags = {
    Name = "${var.project_name}-${var.environment}-storage-dns-zone"
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage" {
  name                  = "${var.project_name}-${var.environment}-storage-dns-link"
  resource_group_name   = azurerm_resource_group.allied.name
  private_dns_zone_name = azurerm_private_dns_zone.storage.name
  virtual_network_id    = azurerm_virtual_network.allied.id
}
