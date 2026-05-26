# ═══════════════════════════════════════════════════════════════════════════════
# AZURE ALLIED VNET MODULE
# Simulates an IRAP-compliant environment for Australian defense operations
# Design principles: Isolated networking, no public endpoints, encryption
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# RESOURCE GROUP
# ─────────────────────────────────────────────

resource "azurerm_resource_group" "allied" {
  name     = "${var.project_name}-${var.environment}-allied-rg"
  location = var.azure_region

  tags = {
    Project        = var.project_name
    Environment    = var.environment
    Classification = "UNCLASSIFIED-DEMO"
    ManagedBy      = "terraform"
  }
}

# ─────────────────────────────────────────────
# VIRTUAL NETWORK — Isolated network boundary
# ─────────────────────────────────────────────

resource "azurerm_virtual_network" "allied" {
  name                = "${var.project_name}-${var.environment}-allied-vnet"
  location            = azurerm_resource_group.allied.location
  resource_group_name = azurerm_resource_group.allied.name
  address_space       = [var.vnet_cidr]

  tags = {
    Name = "${var.project_name}-${var.environment}-allied-vnet"
  }
}

# ─────────────────────────────────────────────
# SUBNETS — Segmented by function
# ─────────────────────────────────────────────

# AKS Node Subnet — Worker nodes live here
resource "azurerm_subnet" "aks_nodes" {
  name                 = "${var.project_name}-${var.environment}-aks-nodes"
  resource_group_name  = azurerm_resource_group.allied.name
  virtual_network_name = azurerm_virtual_network.allied.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 4, 0)]

  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.KeyVault",
    "Microsoft.ContainerRegistry"
  ]
}

# Private Endpoints Subnet — For Key Vault, Storage, ACR
resource "azurerm_subnet" "private_endpoints" {
  name                 = "${var.project_name}-${var.environment}-private-endpoints"
  resource_group_name  = azurerm_resource_group.allied.name
  virtual_network_name = azurerm_virtual_network.allied.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 4, 1)]

  private_endpoint_network_policies = "Enabled"
}

# VPN Gateway Subnet — MUST be named "GatewaySubnet" for Azure
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.allied.name
  virtual_network_name = azurerm_virtual_network.allied.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 4, 2)]
}

# ─────────────────────────────────────────────
# NETWORK SECURITY GROUPS — Stateful filtering
# ─────────────────────────────────────────────

resource "azurerm_network_security_group" "aks_nodes" {
  name                = "${var.project_name}-${var.environment}-aks-nsg"
  location            = azurerm_resource_group.allied.location
  resource_group_name = azurerm_resource_group.allied.name

  # Allow intra-VNet traffic
  security_rule {
    name                       = "AllowVNetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Allow traffic from AWS sovereign VPC (via VPN)
  security_rule {
    name                       = "AllowAWSSovereignInbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.aws_vpc_cidr
    destination_address_prefix = "*"
  }

  # Deny all other inbound from internet
  security_rule {
    name                       = "DenyInternetInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # Allow outbound to VNet and AWS
  security_rule {
    name                       = "AllowVNetOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAWSSovereignOutbound"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = var.aws_vpc_cidr
  }

  # Allow outbound to Azure services (for AKS management)
  security_rule {
    name                       = "AllowAzureServicesOutbound"
    priority                   = 300
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
  }

  # Deny all other outbound to internet
  security_rule {
    name                       = "DenyInternetOutbound"
    priority                   = 4000
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-aks-nsg"
  }
}

# Associate NSG with AKS subnet
resource "azurerm_subnet_network_security_group_association" "aks_nodes" {
  subnet_id                 = azurerm_subnet.aks_nodes.id
  network_security_group_id = azurerm_network_security_group.aks_nodes.id
}

# ─────────────────────────────────────────────
# NETWORK WATCHER FLOW LOGS — Traffic auditing
# ─────────────────────────────────────────────

resource "azurerm_network_watcher" "allied" {
  name                = "${var.project_name}-${var.environment}-network-watcher"
  location            = azurerm_resource_group.allied.location
  resource_group_name = azurerm_resource_group.allied.name
}

resource "azurerm_storage_account" "flow_logs" {
  name                     = replace("${var.project_name}${var.environment}flow", "-", "")
  resource_group_name      = azurerm_resource_group.allied.name
  location                 = azurerm_resource_group.allied.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = {
    Name    = "${var.project_name}-${var.environment}-flow-logs-storage"
    Purpose = "nsg-flow-logs"
  }
}

resource "azurerm_network_watcher_flow_log" "aks_nsg" {
  name                      = "${var.project_name}-${var.environment}-aks-flow-log"
  network_watcher_name      = azurerm_network_watcher.allied.name
  resource_group_name       = azurerm_resource_group.allied.name
  network_security_group_id = azurerm_network_security_group.aks_nodes.id
  storage_account_id        = azurerm_storage_account.flow_logs.id
  enabled                   = true
  version                   = 2

  retention_policy {
    enabled = true
    days    = 90
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.allied.workspace_id
    workspace_region      = azurerm_resource_group.allied.location
    workspace_resource_id = azurerm_log_analytics_workspace.allied.id
    interval_in_minutes   = 10
  }
}

# ─────────────────────────────────────────────
# LOG ANALYTICS WORKSPACE — Central monitoring
# ─────────────────────────────────────────────

resource "azurerm_log_analytics_workspace" "allied" {
  name                = "${var.project_name}-${var.environment}-law"
  location            = azurerm_resource_group.allied.location
  resource_group_name = azurerm_resource_group.allied.name
  sku                 = "PerGB2018"
  retention_in_days   = 90

  tags = {
    Name = "${var.project_name}-${var.environment}-log-analytics"
  }
}
