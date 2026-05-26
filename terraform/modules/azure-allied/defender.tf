# ═══════════════════════════════════════════════════════════════════════════════
# MICROSOFT DEFENDER FOR CLOUD — Security Posture & Threat Protection
# Equivalent to AWS GuardDuty + Security Hub
# ═══════════════════════════════════════════════════════════════════════════════

# Enable Defender for Containers
resource "azurerm_security_center_subscription_pricing" "containers" {
  tier          = "Standard"
  resource_type = "Containers"
}

# Enable Defender for Storage
resource "azurerm_security_center_subscription_pricing" "storage" {
  tier          = "Standard"
  resource_type = "StorageAccounts"
}

# Enable Defender for Key Vault
resource "azurerm_security_center_subscription_pricing" "key_vault" {
  tier          = "Standard"
  resource_type = "KeyVaults"
}

# ─────────────────────────────────────────────
# SECURITY ALERTS — Route to Log Analytics
# ─────────────────────────────────────────────

resource "azurerm_security_center_workspace" "allied" {
  scope        = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  workspace_id = azurerm_log_analytics_workspace.allied.id
}

# ─────────────────────────────────────────────
# ALERT RULES — High severity notifications
# ─────────────────────────────────────────────

resource "azurerm_monitor_action_group" "security" {
  name                = "${var.project_name}-${var.environment}-security-alerts"
  resource_group_name = azurerm_resource_group.allied.name
  short_name          = "SecAlerts"

  tags = {
    Name = "${var.project_name}-${var.environment}-security-action-group"
  }
}

resource "azurerm_monitor_activity_log_alert" "security_alert" {
  name                = "${var.project_name}-${var.environment}-high-severity-alert"
  resource_group_name = azurerm_resource_group.allied.name
  scopes              = ["/subscriptions/${data.azurerm_client_config.current.subscription_id}"]

  criteria {
    category = "Security"
    level    = "Error"
  }

  action {
    action_group_id = azurerm_monitor_action_group.security.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-security-log-alert"
  }
}
