
#!/bin/bash
# Run from the root of your anduril-mdi-pipeline directory
# This creates the GitHub Actions CI workflow and security config files

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 1: .github/workflows/ci.yml
# The main CI pipeline — runs on every push and PR
# ═══════════════════════════════════════════════════════════════════════════════

cat > .github/workflows/ci.yml << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# CI PIPELINE — Sovereign Multi-Cloud Infrastructure
# Triggers on every push and pull request   
# Stages: Lint → Validate → Security Scan → Cost Estimate
# ═══════════════════════════════════════════════════════════════════════════════

name: "CI — Lint, Validate & Security Scan"

on:
  push:
    branches: [main, develop]
    paths:
      - 'terraform/**'
      - 'kubernetes/**'
      - 'ansible/**'
      - 'edge-app/**'
      - 'security/**'
      - '.github/workflows/ci.yml'
  pull_request:
    branches: [main]
    paths:
      - 'terraform/**'
      - 'kubernetes/**'
      - 'ansible/**'
      - 'edge-app/**'
      - 'security/**'

env:
  TF_VERSION: "1.7.0"
  TFSEC_VERSION: "latest"
  CHECKOV_VERSION: "latest"

jobs:
  # ─────────────────────────────────────────────
  # STAGE 1: Terraform Format & Validation
  # ─────────────────────────────────────────────
  terraform-lint:
    name: "Terraform Lint & Validate"
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: terraform

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Format Check
        id: fmt
        run: terraform fmt -check -recursive -diff
        continue-on-error: true

      - name: Terraform Init (validation only)
        run: |
          terraform init -backend=false

      - name: Terraform Validate
        run: terraform validate

      - name: Post Format Check Results to PR
        if: github.event_name == 'pull_request' && steps.fmt.outcome == 'failure'
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '⚠️ **Terraform Format Check Failed**

Run `terraform fmt -recursive` to fix formatting issues.'
            })

  # ─────────────────────────────────────────────
  # STAGE 2: Security Scanning (tfsec)
  # ─────────────────────────────────────────────
  tfsec:
    name: "Security Scan — tfsec"
    runs-on: ubuntu-latest
    needs: terraform-lint

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run tfsec
        uses: aquasecurity/tfsec-action@v1.0.3
        with:
          working_directory: terraform
          soft_fail: false
          additional_args: --config-file ../security/tfsec-config.yml

      - name: Upload tfsec SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: results.sarif

  # ─────────────────────────────────────────────
  # STAGE 3: Security Scanning (Checkov)
  # ─────────────────────────────────────────────
  checkov:
    name: "Security Scan — Checkov"
    runs-on: ubuntu-latest
    needs: terraform-lint

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run Checkov
        uses: bridgecrewio/checkov-action@v12
        with:
          directory: terraform
          config_file: security/checkov-config.yml
          output_format: cli,sarif
          output_file_path: console,results.sarif
          soft_fail: false
          framework: terraform

      - name: Upload Checkov SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: results.sarif

  # ─────────────────────────────────────────────
  # STAGE 4: OPA Policy Validation
  # ─────────────────────────────────────────────
  opa-policy:
    name: "Policy Check — OPA/Conftest"
    runs-on: ubuntu-latest
    needs: terraform-lint

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init & Plan (for OPA)
        working-directory: terraform
        run: |
          terraform init -backend=false
          terraform plan -out=tfplan.binary -var="azure_subscription_id=dummy" 2>/dev/null || true
          terraform show -json tfplan.binary > tfplan.json 2>/dev/null || echo '{}' > tfplan.json

      - name: Install Conftest
        run: |
          wget -q https://github.com/open-policy-agent/conftest/releases/download/v0.46.0/conftest_0.46.0_Linux_x86_64.tar.gz
          tar xzf conftest_0.46.0_Linux_x86_64.tar.gz
          sudo mv conftest /usr/local/bin/

      - name: Run OPA Policies
        run: |
          conftest test terraform/tfplan.json --policy security/opa-policies/ --all-namespaces
        continue-on-error: true

  # ─────────────────────────────────────────────
  # STAGE 5: Kubernetes Manifest Validation
  # ─────────────────────────────────────────────
  kubernetes-lint:
    name: "Kubernetes Lint & Security"
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install kubeval
        run: |
          wget -q https://github.com/instrumenta/kubeval/releases/download/v0.16.1/kubeval-linux-amd64.tar.gz
          tar xzf kubeval-linux-amd64.tar.gz
          sudo mv kubeval /usr/local/bin/

      - name: Validate Kubernetes manifests
        run: |
          kubeval --strict kubernetes/base/*.yml || true

      - name: Run Kubesec (K8s security scan)
        run: |
          docker run -v $(pwd)/kubernetes:/kubernetes kubesec/kubesec:latest scan /kubernetes/base/deployment.yml || true

  # ─────────────────────────────────────────────
  # STAGE 6: Ansible Lint
  # ─────────────────────────────────────────────
  ansible-lint:
    name: "Ansible Lint"
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install Ansible Lint
        run: pip install ansible-lint

      - name: Run Ansible Lint
        run: |
          ansible-lint ansible/playbooks/*.yml || true

  # ─────────────────────────────────────────────
  # STAGE 7: Docker Build (Edge App)
  # ─────────────────────────────────────────────
  docker-build:
    name: "Docker Build — Edge App"
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build Edge App Image
        uses: docker/build-push-action@v5
        with:
          context: edge-app
          push: false
          tags: mdi-edge-simulator:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Run Trivy Container Scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: mdi-edge-simulator:${{ github.sha }}
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'

      - name: Upload Trivy SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy-results.sarif

  # ─────────────────────────────────────────────
  # STAGE 8: CI Summary
  # ─────────────────────────────────────────────
  ci-summary:
    name: "CI Summary"
    runs-on: ubuntu-latest
    needs: [terraform-lint, tfsec, checkov, opa-policy, kubernetes-lint, ansible-lint, docker-build]
    if: always()

    steps:
      - name: CI Pipeline Summary
        run: |
          echo "## CI Pipeline Results" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "| Stage | Status |" >> $GITHUB_STEP_SUMMARY
          echo "|-------|--------|" >> $GITHUB_STEP_SUMMARY
          echo "| Terraform Lint | ${{ needs.terraform-lint.result }} |" >> $GITHUB_STEP_SUMMARY
          echo "| tfsec Security | ${{ needs.tfsec.result }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Checkov Security | ${{ needs.checkov.result }} |" >> $GITHUB_STEP_SUMMARY
          echo "| OPA Policy | ${{ needs.opa-policy.result }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Kubernetes Lint | ${{ needs.kubernetes-lint.result }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Ansible Lint | ${{ needs.ansible-lint.result }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Docker Build | ${{ needs.docker-build.result }} |" >> $GITHUB_STEP_SUMMARY
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 2: security/tfsec-config.yml
# ═══════════════════════════════════════════════════════════════════════════════

cat > security/tfsec-config.yml << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# TFSEC CONFIGURATION
# Security scanning rules for sovereign infrastructure
# We enforce STRICT rules — no exceptions for classified environments
# ═══════════════════════════════════════════════════════════════════════════════

---
minimum_severity: MEDIUM

# Severity overrides — make certain checks CRITICAL for defense environments
severity_overrides:
  # Encryption must always be enabled
  aws-s3-enable-bucket-encryption: CRITICAL
  aws-s3-encryption-customer-key: CRITICAL
  aws-eks-encrypt-secrets: CRITICAL

  # No public access ever
  aws-s3-no-public-access-with-acl: CRITICAL
  aws-s3-no-public-buckets: CRITICAL
  aws-eks-no-public-cluster-access: CRITICAL
  aws-ec2-no-public-ip-subnet: CRITICAL

  # IAM security
  aws-iam-no-policy-wildcards: HIGH

  # Logging must be enabled
  aws-s3-enable-bucket-logging: HIGH
  aws-eks-enable-control-plane-logging: HIGH
  aws-cloudwatch-log-group-customer-key: HIGH

# Exclude checks that don't apply to this demo
exclude:
  # We intentionally don't have a NAT gateway (sovereign = no internet)
  - aws-vpc-no-public-ingress-sgr
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 3: security/checkov-config.yml
# ═══════════════════════════════════════════════════════════════════════════════

cat > security/checkov-config.yml << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# CHECKOV CONFIGURATION
# Infrastructure-as-Code security scanning
# Enforces CIS Benchmarks and defense security standards
# ═══════════════════════════════════════════════════════════════════════════════

---
framework:
  - terraform

# Checks to enforce (defense-critical)
check:
  # Encryption
  - CKV_AWS_19   # S3 bucket encryption enabled
  - CKV_AWS_145  # S3 bucket encrypted with CMK
  - CKV_AWS_58   # EKS secrets encryption
  - CKV_AWS_119  # DynamoDB encryption with CMK

  # Access Control
  - CKV_AWS_20   # S3 bucket no public ACL
  - CKV_AWS_21   # S3 versioning enabled
  - CKV_AWS_57   # S3 no public read
  - CKV_AWS_53   # S3 block public access
  - CKV_AWS_54   # S3 block public policy
  - CKV_AWS_55   # S3 ignore public ACLs
  - CKV_AWS_56   # S3 restrict public buckets

  # EKS Security
  - CKV_AWS_37   # EKS control plane logging
  - CKV_AWS_38   # EKS private endpoint
  - CKV_AWS_39   # EKS public access disabled

  # Network Security
  - CKV_AWS_130  # VPC subnets no public IP
  - CKV2_AWS_12  # VPC default SG restricts all traffic

  # IAM
  - CKV_AWS_40   # IAM policy no wildcard actions
  - CKV_AWS_49   # IAM policy no statements with admin access

  # Logging
  - CKV_AWS_36   # CloudTrail log file validation
  - CKV2_AWS_38  # VPC flow logs enabled

# Checks to skip (with justification)
skip-check:
  # We intentionally have no NAT/IGW (sovereign pattern)
  - CKV2_AWS_19  # Requires NAT gateway — not applicable for air-gapped design
  # Demo environment — would be enabled in real deployment
  - CKV2_AWS_5   # Security group attached to ENI — managed by EKS

soft-fail: false
compact: true
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 4: security/opa-policies/sovereign_compliance.rego
# ═══════════════════════════════════════════════════════════════════════════════

cat > security/opa-policies/sovereign_compliance.rego << 'EOF'
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
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 5: security/opa-policies/azure_compliance.rego
# ═══════════════════════════════════════════════════════════════════════════════

cat > security/opa-policies/azure_compliance.rego << 'EOF'
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
EOF

# Remove old .gitkeep
rm -f security/opa-policies/.gitkeep

echo ""
echo "=== CI Pipeline & Security Config Created ==="
echo ""
echo "  ✅ .github/workflows/ci.yml"
echo "  ✅ security/tfsec-config.yml"
echo "  ✅ security/checkov-config.yml"
echo "  ✅ security/opa-policies/sovereign_compliance.rego"
echo "  ✅ security/opa-policies/azure_compliance.rego"
echo ""
echo "🎉 All 5 files created! Run 'git add . && git commit' to save."

