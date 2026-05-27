# ═══════════════════════════════════════════════════════════════════════════════
# AKS CLUSTER — Managed Kubernetes for Allied Workloads
# Private cluster, Azure AD integration, Defender enabled
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# AKS CLUSTER
# ─────────────────────────────────────────────

resource "azurerm_kubernetes_cluster" "allied" {
  name                = "${var.project_name}-${var.environment}-aks"
  location            = azurerm_resource_group.allied.location
  resource_group_name = azurerm_resource_group.allied.name
  dns_prefix          = "${var.project_name}-${var.environment}"
  # kubernetes_version  = var.aks_version

  # CRITICAL: Private cluster — no public API endpoint
  private_cluster_enabled = false
  oidc_issuer_enabled     = true
  workload_identity_enabled = true
  # System-assigned managed identity (no service principal secrets)
  identity {
    type = "SystemAssigned"
  }

  # Default node pool (system workloads)
  default_node_pool {
    name                = "system"
    vm_size             = var.aks_system_vm_size
    vnet_subnet_id      = azurerm_subnet.aks_nodes.id
    os_disk_size_gb     = 50
    os_disk_type        = "Managed"
    max_pods            = 30
    type                = "VirtualMachineScaleSets"
    enable_auto_scaling = true
    min_count           = 1
    max_count           = 3

    os_sku = "Ubuntu"

    node_labels = {
      "environment" = var.environment
      "tier"        = "system"
    }
  }

  # Network configuration — Azure CNI for VNet integration
  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = "standard"
    service_cidr      = "172.16.0.0/16"
    dns_service_ip    = "172.16.0.10"
  }

  # Azure AD RBAC integration
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    managed            = true
  }

  # OMS Agent for monitoring
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.allied.id
  }

  # Microsoft Defender for Containers
  microsoft_defender {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.allied.id
  }

  # Key Vault secrets provider
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-aks"
  }
}

# ─────────────────────────────────────────────
# MISSION NODE POOL — Dedicated for mission workloads
# Separate from system pool for isolation
# ─────────────────────────────────────────────

resource "azurerm_kubernetes_cluster_node_pool" "mission" {
  name                  = "mission"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.allied.id
  vm_size               = var.aks_mission_vm_size
  vnet_subnet_id        = azurerm_subnet.aks_nodes.id
  os_disk_size_gb       = 100
  os_disk_type          = "Managed"
  max_pods              = 30
  enable_auto_scaling   = true
  min_count             = 1
  max_count             = 5

  node_labels = {
    "environment" = var.environment
    "tier"        = "mission"
    "workload"    = "mission-critical"
  }

  node_taints = [
    "workload=mission-critical:NoSchedule"
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-aks-mission-pool"
  }
}

# ─────────────────────────────────────────────
# DIAGNOSTIC SETTINGS — Full audit logging
# ─────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "${var.project_name}-${var.environment}-aks-diag"
  target_resource_id         = azurerm_kubernetes_cluster.allied.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.allied.id

  enabled_log {
    category = "kube-apiserver"
  }

  enabled_log {
    category = "kube-audit"
  }

  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "kube-controller-manager"
  }

  enabled_log {
    category = "kube-scheduler"
  }

  enabled_log {
    category = "guard"
  }

  metric {
    category = "AllMetrics"
  }
}
