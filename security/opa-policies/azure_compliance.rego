# ═══════════════════════════════════════════════════════════════════════════════
# OPA POLICY — Azure Allied Infrastructure Compliance
# Enforces IRAP-aligned security requirements for Azure resources
# ═══════════════════════════════════════════════════════════════════════════════

package azure_compliance

import input as tfplan

# ─────────────────────────────────────────────
# RULE: AKS must be private cluster
# ─────────────────────────────────────────────

deny[msg] {
    resource := tfplan.resource_changes[_]
    resource.type == "azurerm_kubernetes_cluster"
    resource.change.after.private_cluster_enabled != true
    msg := sprintf("AKS cluster '%s' must be private (IRAP requirement)", [resource.address])
}

# ─────────────────────────────────────────────
# RULE: Key Vault must have purge protection
# ─────────────────────────────────────────────

deny[msg] {
    resource := tfplan.resource_changes[_]
    resource.type == "azurerm_key_vault"
    resource.change.after.purge_protection_enabled != true
    msg := sprintf("Key Vault '%s' must have purge protection enabled", [resource.address])
}

# ─────────────────────────────────────────────
# RULE: Storage accounts must enforce TLS 1.2+
# ─────────────────────────────────────────────

deny[msg] {
    resource := tfplan.resource_changes[_]
    resource.type == "azurerm_storage_account"
    resource.change.after.min_tls_version != "TLS1_2"
    msg := sprintf("Storage account '%s' must enforce TLS 1.2 minimum", [resource.address])
}

# ─────────────────────────────────────────────
# RULE: No public network access on storage
# ─────────────────────────────────────────────

deny[msg] {
    resource := tfplan.resource_changes[_]
    resource.type == "azurerm_storage_account"
    resource.change.after.public_network_access_enabled == true
    msg := sprintf("Storage account '%s' must not allow public network access", [resource.address])
}

# ─────────────────────────────────────────────
# RULE: Key Vault must use RBAC (not access policies)
# ─────────────────────────────────────────────

deny[msg] {
    resource := tfplan.resource_changes[_]
    resource.type == "azurerm_key_vault"
    resource.change.after.enable_rbac_authorization != true
    msg := sprintf("Key Vault '%s' must use RBAC authorization (not access policies)", [resource.address])
}

# ─────────────────────────────────────────────
# RULE: NSGs must deny internet inbound
# ─────────────────────────────────────────────

warn[msg] {
    resource := tfplan.resource_changes[_]
    resource.type == "azurerm_network_security_group"
    rule := resource.change.after.security_rule[_]
    rule.direction == "Inbound"
    rule.access == "Allow"
    rule.source_address_prefix == "Internet"
    msg := sprintf("NSG '%s' has a rule allowing inbound from Internet", [resource.address])
}
