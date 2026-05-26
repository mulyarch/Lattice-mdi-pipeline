# ═══════════════════════════════════════════════════════════════════════════════
# OPA POLICY — Sovereign Infrastructure Compliance
# Custom policies that go beyond tfsec/Checkov
# Enforces organization-specific defense requirements
# ═══════════════════════════════════════════════════════════════════════════════

package sovereign_compliance

import input as tfplan

# ─────────────────────────────────────────────
# RULE: All S3 buckets must use KMS encryption
# ─────────────────────────────────────────────

deny[msg] {
    resource := tfplan.resource_changes[_]
    resource.type == "aws_s3_bucket_server_side_encryption_configuration"
    rule := resource.change.after.rule[_]
    rule.apply_server_side_encryption_by_default[_].sse_algorithm != "aws:kms"
    msg := sprintf("S3 bucket '%s' must use aws:kms encryption (sovereign requirement)", [resource.address])
}

# ─────────────────────────────────────────────
# RULE: No public subnets allowed
# ─────────────────────────────────────────────

deny[msg] {
    resource := tfplan.resource_changes[_]
    resource.type == "aws_subnet"
    resource.change.after.map_public_ip_on_launch == true
    msg := sprintf("Subnet '%s' has public IP mapping enabled (forbidden in sovereign environment)", [resource.address])
}

# ─────────────────────────────────────────────
# RULE: EKS must have private endpoint only
# ─────────────────────────────────────────────

deny[msg] {
    resource := tfplan.resource_changes[_]
    resource.type == "aws_eks_cluster"
    vpc_config := resource.change.after.vpc_config[_]
    vpc_config.endpoint_public_access == true
    msg := sprintf("EKS cluster '%s' has public endpoint enabled (forbidden in sovereign environment)", [resource.address])
}

# ─────────────────────────────────────────────
# RULE: All resources must have required tags
# ─────────────────────────────────────────────

required_tags := {"Project", "Environment", "ManagedBy"}

deny[msg] {
    resource := tfplan.resource_changes[_]
    resource.change.after.tags != null
    tags := resource.change.after.tags
    required_tag := required_tags[_]
    not tags[required_tag]
    msg := sprintf("Resource '%s' is missing required tag: '%s'", [resource.address, required_tag])
}

# ─────────────────────────────────────────────
# RULE: IMDSv2 must be required on all EC2/launch templates
# ─────────────────────────────────────────────

deny[msg] {
    resource := tfplan.resource_changes[_]
    resource.type == "aws_launch_template"
    metadata := resource.change.after.metadata_options[_]
    metadata.http_tokens != "required"
    msg := sprintf("Launch template '%s' must enforce IMDSv2 (http_tokens = required)", [resource.address])
}

# ─────────────────────────────────────────────
# RULE: VPC Flow Logs must be enabled
# ─────────────────────────────────────────────

warn[msg] {
    resource := tfplan.resource_changes[_]
    resource.type == "aws_vpc"
    not has_flow_log(resource.change.after.id)
    msg := sprintf("VPC '%s' should have flow logs enabled for compliance", [resource.address])
}

has_flow_log(vpc_id) {
    resource := tfplan.resource_changes[_]
    resource.type == "aws_flow_log"
    resource.change.after.vpc_id == vpc_id
}

# ─────────────────────────────────────────────
# RULE: Security groups must not allow 0.0.0.0/0 ingress
# ─────────────────────────────────────────────

deny[msg] {
    resource := tfplan.resource_changes[_]
    resource.type == "aws_security_group_rule"
    resource.change.after.type == "ingress"
    resource.change.after.cidr_blocks[_] == "0.0.0.0/0"
    msg := sprintf("Security group rule '%s' allows ingress from 0.0.0.0/0 (forbidden in sovereign environment)", [resource.address])
}

# ─────────────────────────────────────────────
# RULE: KMS keys must have rotation enabled
# ─────────────────────────────────────────────

deny[msg] {
    resource := tfplan.resource_changes[_]
    resource.type == "aws_kms_key"
    resource.change.after.enable_key_rotation != true
    msg := sprintf("KMS key '%s' must have automatic key rotation enabled", [resource.address])
}
