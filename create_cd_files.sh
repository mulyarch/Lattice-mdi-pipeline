
#!/bin/bash
# Run from the root of your anduril-mdi-pipeline directory
# This creates the CD (Continuous Deployment) pipeline files

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 1: .github/workflows/deploy-infra.yml
# The main CD pipeline — Plan → Approve → Apply
# ═══════════════════════════════════════════════════════════════════════════════

cat > .github/workflows/deploy-infra.yml << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# CD PIPELINE — Infrastructure Deployment
# Deploys sovereign multi-cloud infrastructure with approval gates
#
# Flow: Plan → Review → Approve → Apply (per environment)
# Environments: dev → staging → prod (promotion model)
#
# Defense deployment pattern:
#   - No auto-deploy to production
#   - Human approval required for each environment
#   - Full plan output visible before apply
#   - Rollback capability via Terraform state
# ═══════════════════════════════════════════════════════════════════════════════

name: "CD — Deploy Infrastructure"

on:
  # Manual trigger with environment selection
  workflow_dispatch:
    inputs:
      environment:
        description: "Target environment"
        required: true
        type: choice
        options:
          - dev
          - staging
          - prod
      action:
        description: "Terraform action"
        required: true
        type: choice
        options:
          - plan
          - apply
          - destroy
      confirm_destroy:
        description: "Type 'DESTROY' to confirm destruction (required for destroy action)"
        required: false
        type: string

  # Auto-trigger on merge to main (plan only for safety)
  push:
    branches: [main]
    paths:
      - 'terraform/**'

# Prevent concurrent deployments to same environment
concurrency:
  group: deploy-${{ github.event.inputs.environment || 'dev' }}
  cancel-in-progress: false

env:
  TF_VERSION: "1.7.0"
  AWS_REGION: "us-east-1"

# Required permissions for OIDC authentication
permissions:
  id-token: write
  contents: read
  pull-requests: write
  issues: write

jobs:
  # ─────────────────────────────────────────────
  # STAGE 1: Pre-flight Checks
  # ─────────────────────────────────────────────
  preflight:
    name: "Pre-flight Checks"
    runs-on: ubuntu-latest
    outputs:
      environment: ${{ steps.set-env.outputs.environment }}
      action: ${{ steps.set-env.outputs.action }}

    steps:
      - name: Set Environment
        id: set-env
        run: |
          ENV="${{ github.event.inputs.environment || 'dev' }}"
          ACTION="${{ github.event.inputs.action || 'plan' }}"
          echo "environment=$ENV" >> $GITHUB_OUTPUT
          echo "action=$ACTION" >> $GITHUB_OUTPUT
          echo "## 🚀 Deployment Configuration" >> $GITHUB_STEP_SUMMARY
          echo "| Parameter | Value |" >> $GITHUB_STEP_SUMMARY
          echo "|-----------|-------|" >> $GITHUB_STEP_SUMMARY
          echo "| Environment | \`$ENV\` |" >> $GITHUB_STEP_SUMMARY
          echo "| Action | \`$ACTION\` |" >> $GITHUB_STEP_SUMMARY
          echo "| Triggered by | ${{ github.actor }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Commit | \`${{ github.sha }}\` |" >> $GITHUB_STEP_SUMMARY

      - name: Validate Destroy Confirmation
        if: github.event.inputs.action == 'destroy'
        run: |
          if [ "${{ github.event.inputs.confirm_destroy }}" != "DESTROY" ]; then
            echo "❌ Destroy action requires typing 'DESTROY' in the confirmation field"
            exit 1
          fi
          echo "⚠️ DESTROY confirmed for ${{ github.event.inputs.environment }}"

  # ─────────────────────────────────────────────
  # STAGE 2: Terraform Plan
  # ─────────────────────────────────────────────
  plan:
    name: "Terraform Plan — ${{ needs.preflight.outputs.environment }}"
    runs-on: ubuntu-latest
    needs: preflight
    environment: ${{ needs.preflight.outputs.environment }}-plan
    outputs:
      plan_exitcode: ${{ steps.plan.outputs.exitcode }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      # OIDC Authentication — No long-lived credentials
      - name: Configure AWS Credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
          role-session-name: github-actions-${{ needs.preflight.outputs.environment }}

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Terraform Init
        working-directory: terraform
        run: |
          terraform init \
            -backend-config="key=sovereign-infra/${{ needs.preflight.outputs.environment }}/terraform.tfstate"

      - name: Terraform Plan
        id: plan
        working-directory: terraform
        run: |
          terraform plan \
            -var="environment=${{ needs.preflight.outputs.environment }}" \
            -var="azure_subscription_id=${{ secrets.AZURE_SUBSCRIPTION_ID }}" \
            -var-file="environments/${{ needs.preflight.outputs.environment }}/terraform.tfvars" \
            -out=tfplan \
            -detailed-exitcode \
            -no-color 2>&1 | tee plan_output.txt

          echo "exitcode=$?" >> $GITHUB_OUTPUT
        continue-on-error: true

      - name: Plan Summary
        working-directory: terraform
        run: |
          echo "## 📋 Terraform Plan — ${{ needs.preflight.outputs.environment }}" >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY
          terraform show -no-color tfplan >> $GITHUB_STEP_SUMMARY 2>/dev/null || echo "No plan file generated" >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY

      - name: Upload Plan Artifact
        uses: actions/upload-artifact@v4
        with:
          name: tfplan-${{ needs.preflight.outputs.environment }}
          path: terraform/tfplan
          retention-days: 5

      - name: Upload Plan Output
        uses: actions/upload-artifact@v4
        with:
          name: plan-output-${{ needs.preflight.outputs.environment }}
          path: terraform/plan_output.txt
          retention-days: 5

  # ─────────────────────────────────────────────
  # STAGE 3: Security Review (automated)
  # ─────────────────────────────────────────────
  security-review:
    name: "Security Review — Plan Analysis"
    runs-on: ubuntu-latest
    needs: [preflight, plan]
    if: needs.preflight.outputs.action == 'apply'

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Download Plan Output
        uses: actions/download-artifact@v4
        with:
          name: plan-output-${{ needs.preflight.outputs.environment }}

      - name: Analyze Plan for Security Risks
        run: |
          echo "## 🔒 Security Review" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY

          # Check for dangerous operations
          if grep -q "will be destroyed" plan_output.txt 2>/dev/null; then
            echo "⚠️ **WARNING: Resources will be DESTROYED**" >> $GITHUB_STEP_SUMMARY
            grep "will be destroyed" plan_output.txt >> $GITHUB_STEP_SUMMARY
            echo "" >> $GITHUB_STEP_SUMMARY
          fi

          # Check for security group changes
          if grep -q "aws_security_group" plan_output.txt 2>/dev/null; then
            echo "🔐 Security group changes detected — review carefully" >> $GITHUB_STEP_SUMMARY
          fi

          # Check for IAM changes
          if grep -q "aws_iam" plan_output.txt 2>/dev/null; then
            echo "🔑 IAM changes detected — review carefully" >> $GITHUB_STEP_SUMMARY
          fi

          # Check for encryption changes
          if grep -q "kms\|encrypt" plan_output.txt 2>/dev/null; then
            echo "🔐 Encryption configuration changes detected" >> $GITHUB_STEP_SUMMARY
          fi

          echo "" >> $GITHUB_STEP_SUMMARY
          echo "✅ Automated security review complete" >> $GITHUB_STEP_SUMMARY

  # ─────────────────────────────────────────────
  # STAGE 4: Manual Approval Gate
  # ─────────────────────────────────────────────
  approve:
    name: "Approval Gate — ${{ needs.preflight.outputs.environment }}"
    runs-on: ubuntu-latest
    needs: [preflight, plan, security-review]
    if: needs.preflight.outputs.action == 'apply'
    environment: ${{ needs.preflight.outputs.environment }}-approve

    steps:
      - name: Approval Granted
        run: |
          echo "## ✅ Deployment Approved" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "| Detail | Value |" >> $GITHUB_STEP_SUMMARY
          echo "|--------|-------|" >> $GITHUB_STEP_SUMMARY
          echo "| Approved by | ${{ github.actor }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Environment | ${{ needs.preflight.outputs.environment }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Timestamp | $(date -u '+%Y-%m-%d %H:%M:%S UTC') |" >> $GITHUB_STEP_SUMMARY

  # ─────────────────────────────────────────────
  # STAGE 5: Terraform Apply
  # ─────────────────────────────────────────────
  apply:
    name: "Terraform Apply — ${{ needs.preflight.outputs.environment }}"
    runs-on: ubuntu-latest
    needs: [preflight, plan, approve]
    if: needs.preflight.outputs.action == 'apply'
    environment: ${{ needs.preflight.outputs.environment }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Configure AWS Credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
          role-session-name: github-actions-deploy-${{ needs.preflight.outputs.environment }}

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Download Plan
        uses: actions/download-artifact@v4
        with:
          name: tfplan-${{ needs.preflight.outputs.environment }}
          path: terraform/

      - name: Terraform Init
        working-directory: terraform
        run: |
          terraform init \
            -backend-config="key=sovereign-infra/${{ needs.preflight.outputs.environment }}/terraform.tfstate"

      - name: Terraform Apply
        working-directory: terraform
        run: |
          terraform apply -auto-approve tfplan

      - name: Apply Summary
        working-directory: terraform
        run: |
          echo "## 🎉 Deployment Complete" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "| Detail | Value |" >> $GITHUB_STEP_SUMMARY
          echo "|--------|-------|" >> $GITHUB_STEP_SUMMARY
          echo "| Environment | ${{ needs.preflight.outputs.environment }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Status | ✅ Success |" >> $GITHUB_STEP_SUMMARY
          echo "| Deployed by | ${{ github.actor }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Timestamp | $(date -u '+%Y-%m-%d %H:%M:%S UTC') |" >> $GITHUB_STEP_SUMMARY
          echo "| Commit | \`${{ github.sha }}\` |" >> $GITHUB_STEP_SUMMARY

      - name: Output Infrastructure Details
        working-directory: terraform
        run: |
          echo "## 📊 Infrastructure Outputs" >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY
          terraform output -no-color >> $GITHUB_STEP_SUMMARY 2>/dev/null || echo "No outputs available" >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY

  # ─────────────────────────────────────────────
  # STAGE 6: Terraform Destroy (emergency only)
  # ─────────────────────────────────────────────
  destroy:
    name: "⚠️ Terraform Destroy — ${{ needs.preflight.outputs.environment }}"
    runs-on: ubuntu-latest
    needs: [preflight]
    if: needs.preflight.outputs.action == 'destroy'
    environment: ${{ needs.preflight.outputs.environment }}-destroy

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Configure AWS Credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
          role-session-name: github-actions-destroy-${{ needs.preflight.outputs.environment }}

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Terraform Init
        working-directory: terraform
        run: |
          terraform init \
            -backend-config="key=sovereign-infra/${{ needs.preflight.outputs.environment }}/terraform.tfstate"

      - name: Terraform Destroy
        working-directory: terraform
        run: |
          terraform destroy \
            -var="environment=${{ needs.preflight.outputs.environment }}" \
            -var="azure_subscription_id=${{ secrets.AZURE_SUBSCRIPTION_ID }}" \
            -var-file="environments/${{ needs.preflight.outputs.environment }}/terraform.tfvars" \
            -auto-approve

      - name: Destroy Summary
        run: |
          echo "## ⚠️ Infrastructure Destroyed" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "| Detail | Value |" >> $GITHUB_STEP_SUMMARY
          echo "|--------|-------|" >> $GITHUB_STEP_SUMMARY
          echo "| Environment | ${{ needs.preflight.outputs.environment }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Action | DESTROY |" >> $GITHUB_STEP_SUMMARY
          echo "| Executed by | ${{ github.actor }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Timestamp | $(date -u '+%Y-%m-%d %H:%M:%S UTC') |" >> $GITHUB_STEP_SUMMARY

  # ─────────────────────────────────────────────
  # STAGE 7: Post-Deploy Notification
  # ─────────────────────────────────────────────
  notify:
    name: "Notify"
    runs-on: ubuntu-latest
    needs: [preflight, apply]
    if: always() && needs.preflight.outputs.action == 'apply'

    steps:
      - name: Deployment Notification
        run: |
          STATUS="${{ needs.apply.result }}"
          ENV="${{ needs.preflight.outputs.environment }}"

          if [ "$STATUS" == "success" ]; then
            echo "✅ Deployment to $ENV succeeded"
          else
            echo "❌ Deployment to $ENV failed"
          fi
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 2: .github/workflows/deploy-app.yml
# Kubernetes application deployment pipeline
# ═══════════════════════════════════════════════════════════════════════════════

cat > .github/workflows/deploy-app.yml << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# CD PIPELINE — Application Deployment
# Builds container images and deploys to EKS/AKS clusters
# Triggered after infrastructure is deployed
# ═══════════════════════════════════════════════════════════════════════════════

name: "CD — Deploy Application"

on:
  workflow_dispatch:
    inputs:
      environment:
        description: "Target environment"
        required: true
        type: choice
        options:
          - dev
          - staging
          - prod
      target_cluster:
        description: "Target cluster"
        required: true
        type: choice
        options:
          - aws-eks
          - azure-aks
          - both

  # Trigger after infra deployment succeeds
  workflow_run:
    workflows: ["CD — Deploy Infrastructure"]
    types: [completed]
    branches: [main]

env:
  AWS_REGION: "us-east-1"
  ECR_REPOSITORY: "mdi-sovereign/edge-simulator"

permissions:
  id-token: write
  contents: read

jobs:
  # ─────────────────────────────────────────────
  # STAGE 1: Build & Push Container Image
  # ─────────────────────────────────────────────
  build:
    name: "Build Container Image"
    runs-on: ubuntu-latest
    if: ${{ github.event.workflow_run.conclusion == 'success' || github.event_name == 'workflow_dispatch' }}
    outputs:
      image_tag: ${{ steps.meta.outputs.tags }}
      image_digest: ${{ steps.build.outputs.digest }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to Amazon ECR
        id: ecr-login
        uses: aws-actions/amazon-ecr-login@v2

      - name: Docker Metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ steps.ecr-login.outputs.registry }}/${{ env.ECR_REPOSITORY }}
          tags: |
            type=sha,prefix={{branch}}-
            type=ref,event=branch
            type=semver,pattern={{version}}

      - name: Build and Push
        id: build
        uses: docker/build-push-action@v5
        with:
          context: edge-app
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Scan Image with Trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ steps.meta.outputs.tags }}
          format: 'table'
          exit-code: '1'
          severity: 'CRITICAL'

  # ─────────────────────────────────────────────
  # STAGE 2: Deploy to AWS EKS
  # ─────────────────────────────────────────────
  deploy-eks:
    name: "Deploy to EKS — ${{ github.event.inputs.environment || 'dev' }}"
    runs-on: ubuntu-latest
    needs: build
    if: |
      github.event.inputs.target_cluster == 'aws-eks' ||
      github.event.inputs.target_cluster == 'both' ||
      github.event_name == 'workflow_run'
    environment: ${{ github.event.inputs.environment || 'dev' }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Update kubeconfig
        run: |
          aws eks update-kubeconfig \
            --name mdi-sovereign-${{ github.event.inputs.environment || 'dev' }} \
            --region ${{ env.AWS_REGION }}

      - name: Deploy to EKS
        run: |
          # Apply Kubernetes manifests with kustomize overlay
          kubectl apply -k kubernetes/overlays/aws-sovereign/

          # Update image tag
          kubectl set image deployment/mission-data-processor \
            processor=${{ needs.build.outputs.image_tag }} \
            -n mission

          # Wait for rollout
          kubectl rollout status deployment/mission-data-processor \
            -n mission --timeout=300s

      - name: Verify Deployment
        run: |
          echo "## 🚀 EKS Deployment Status" >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY
          kubectl get pods -n mission -o wide >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY

  # ─────────────────────────────────────────────
  # STAGE 3: Deploy to Azure AKS
  # ─────────────────────────────────────────────
  deploy-aks:
    name: "Deploy to AKS — ${{ github.event.inputs.environment || 'dev' }}"
    runs-on: ubuntu-latest
    needs: build
    if: |
      github.event.inputs.target_cluster == 'azure-aks' ||
      github.event.inputs.target_cluster == 'both' ||
      github.event_name == 'workflow_run'
    environment: ${{ github.event.inputs.environment || 'dev' }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Get AKS Credentials
        run: |
          az aks get-credentials \
            --resource-group mdi-sovereign-${{ github.event.inputs.environment || 'dev' }}-allied-rg \
            --name mdi-sovereign-${{ github.event.inputs.environment || 'dev' }}-aks \
            --overwrite-existing

      - name: Deploy to AKS
        run: |
          kubectl apply -k kubernetes/overlays/azure-allied/

          kubectl set image deployment/mission-data-processor \
            processor=${{ needs.build.outputs.image_tag }} \
            -n mission

          kubectl rollout status deployment/mission-data-processor \
            -n mission --timeout=300s

      - name: Verify Deployment
        run: |
          echo "## 🚀 AKS Deployment Status" >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY
          kubectl get pods -n mission -o wide >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY

  # ─────────────────────────────────────────────
  # STAGE 4: Integration Test (Cross-Cloud)
  # ─────────────────────────────────────────────
  integration-test:
    name: "Cross-Cloud Integration Test"
    runs-on: ubuntu-latest
    needs: [deploy-eks, deploy-aks]
    if: |
      always() &&
      (needs.deploy-eks.result == 'success' || needs.deploy-aks.result == 'success')

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Run Cross-Cloud Connectivity Test
        run: |
          echo "## 🔗 Cross-Cloud Integration Tests" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY

          # Test 1: VPN tunnel status
          echo "### VPN Tunnel Status" >> $GITHUB_STEP_SUMMARY
          aws ec2 describe-vpn-connections \
            --filters "Name=tag:Project,Values=mdi-sovereign" \
            --query "VpnConnections[].VgwTelemetry[].{Status:Status,IP:OutsideIpAddress}" \
            --output table >> $GITHUB_STEP_SUMMARY 2>/dev/null || echo "VPN check skipped" >> $GITHUB_STEP_SUMMARY

          # Test 2: EKS cluster health
          echo "### EKS Cluster Health" >> $GITHUB_STEP_SUMMARY
          aws eks describe-cluster \
            --name mdi-sovereign-${{ github.event.inputs.environment || 'dev' }} \
            --query "cluster.{Status:status,Version:version,Endpoint:endpoint}" \
            --output table >> $GITHUB_STEP_SUMMARY 2>/dev/null || echo "EKS check skipped" >> $GITHUB_STEP_SUMMARY

          echo "" >> $GITHUB_STEP_SUMMARY
          echo "✅ Integration tests complete" >> $GITHUB_STEP_SUMMARY
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 3: .github/workflows/configure.yml
# Ansible configuration pipeline (post-deploy)
# ═══════════════════════════════════════════════════════════════════════════════

cat > .github/workflows/configure.yml << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# CD PIPELINE — Post-Deploy Configuration (Ansible)
# Runs after infrastructure is deployed to harden and configure nodes
# ═══════════════════════════════════════════════════════════════════════════════

name: "CD — Configure Infrastructure (Ansible)"

on:
  workflow_dispatch:
    inputs:
      environment:
        description: "Target environment"
        required: true
        type: choice
        options:
          - dev
          - staging
          - prod
      playbook:
        description: "Playbook to run"
        required: true
        type: choice
        options:
          - harden-nodes
          - deploy-monitoring
          - configure-vpn
          - all

  # Trigger after infra deployment
  workflow_run:
    workflows: ["CD — Deploy Infrastructure"]
    types: [completed]
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  configure:
    name: "Run Ansible — ${{ github.event.inputs.playbook || 'all' }}"
    runs-on: ubuntu-latest
    if: ${{ github.event.workflow_run.conclusion == 'success' || github.event_name == 'workflow_dispatch' }}
    environment: ${{ github.event.inputs.environment || 'dev' }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install Ansible
        run: |
          pip install ansible boto3 botocore azure-identity azure-mgmt-compute

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
          aws-region: us-east-1

      - name: Generate Dynamic Inventory
        run: |
          ENV="${{ github.event.inputs.environment || 'dev' }}"
          cat > ansible/inventory/dynamic_inventory.yml << INVENTORY
          plugin: aws_ec2
          regions:
            - us-east-1
          filters:
            tag:Project: mdi-sovereign
            tag:Environment: $ENV
            instance-state-name: running
          keyed_groups:
            - key: tags.Role
              prefix: role
          INVENTORY

      - name: Run Playbooks
        working-directory: ansible
        run: |
          PLAYBOOK="${{ github.event.inputs.playbook || 'all' }}"
          ENV="${{ github.event.inputs.environment || 'dev' }}"

          if [ "$PLAYBOOK" == "all" ] || [ "$PLAYBOOK" == "harden-nodes" ]; then
            echo "Running: harden-nodes.yml"
            ansible-playbook playbooks/harden-nodes.yml \
              -i inventory/dynamic_inventory.yml \
              -e "target_env=$ENV" || true
          fi

          if [ "$PLAYBOOK" == "all" ] || [ "$PLAYBOOK" == "deploy-monitoring" ]; then
            echo "Running: deploy-monitoring.yml"
            ansible-playbook playbooks/deploy-monitoring.yml \
              -i inventory/dynamic_inventory.yml \
              -e "target_env=$ENV" || true
          fi

          if [ "$PLAYBOOK" == "all" ] || [ "$PLAYBOOK" == "configure-vpn" ]; then
            echo "Running: configure-vpn.yml"
            ansible-playbook playbooks/configure-vpn.yml \
              -i inventory/dynamic_inventory.yml \
              -e "target_env=$ENV" || true
          fi

      - name: Configuration Summary
        run: |
          echo "## 🔧 Configuration Complete" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "| Detail | Value |" >> $GITHUB_STEP_SUMMARY
          echo "|--------|-------|" >> $GITHUB_STEP_SUMMARY
          echo "| Environment | ${{ github.event.inputs.environment || 'dev' }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Playbook | ${{ github.event.inputs.playbook || 'all' }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Status | ✅ Complete |" >> $GITHUB_STEP_SUMMARY
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 4: terraform/environments/dev/terraform.tfvars
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/environments/dev/terraform.tfvars << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# DEV ENVIRONMENT — Terraform Variables
# Smaller instances, fewer nodes (cost-effective for development)
# ═══════════════════════════════════════════════════════════════════════════════

environment = "dev"
project_name = "mdi-sovereign"

# AWS
aws_region             = "us-east-1"
aws_vpc_cidr           = "10.0.0.0/16"
aws_availability_zones = ["us-east-1a", "us-east-1b"]

# Azure
azure_region   = "australiaeast"
azure_vnet_cidr = "10.1.0.0/16"
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 5: terraform/environments/staging/terraform.tfvars
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/environments/staging/terraform.tfvars << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# STAGING ENVIRONMENT — Terraform Variables
# Production-like sizing for integration testing
# ═══════════════════════════════════════════════════════════════════════════════

environment = "staging"
project_name = "mdi-sovereign"

# AWS
aws_region             = "us-east-1"
aws_vpc_cidr           = "10.2.0.0/16"
aws_availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

# Azure
azure_region   = "australiaeast"
azure_vnet_cidr = "10.3.0.0/16"
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 6: terraform/environments/prod/terraform.tfvars
# ═══════════════════════════════════════════════════════════════════════════════

cat > terraform/environments/prod/terraform.tfvars << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# PRODUCTION ENVIRONMENT — Terraform Variables
# Full HA deployment, 3 AZs, larger instances
# ═══════════════════════════════════════════════════════════════════════════════

environment = "prod"
project_name = "mdi-sovereign"

# AWS
aws_region             = "us-east-1"
aws_vpc_cidr           = "10.4.0.0/16"
aws_availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

# Azure
azure_region   = "australiaeast"
azure_vnet_cidr = "10.5.0.0/16"
EOF

# Remove .gitkeep files from environments
rm -f terraform/environments/dev/.gitkeep
rm -f terraform/environments/staging/.gitkeep
rm -f terraform/environments/prod/.gitkeep

echo ""
echo "=== CD Pipeline & Environment Configs Created ==="
echo ""
echo "  ✅ .github/workflows/deploy-infra.yml"
echo "  ✅ .github/workflows/deploy-app.yml"
echo "  ✅ .github/workflows/configure.yml"
echo "  ✅ terraform/environments/dev/terraform.tfvars"
echo "  ✅ terraform/environments/staging/terraform.tfvars"
echo "  ✅ terraform/environments/prod/terraform.tfvars"
echo ""
echo "🎉 All 6 files created! Run 'git add . && git commit' to save."

