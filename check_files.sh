#!/bin/bash

# Run from the root of your anduril-mdi-pipeline directory
echo "=== Checking Project Files ==="
echo ""

FILES=(
  # Step 1 - Project Structure
  ".gitignore"
  "README.md"
  ".github/workflows/ci.yml"
  ".github/workflows/deploy-infra.yml"
  ".github/workflows/configure.yml"
  ".github/workflows/deploy-app.yml"

  # Step 2A - Providers
  "terraform/providers.tf"

  # Step 2B - Backend
  "terraform/backend.tf"

  # Step 2C - Root Variables
  "terraform/variables.tf"

  # Step 2D - AWS Sovereign VPC Module
  "terraform/modules/aws-sovereign/main.tf"

  # Step 2E - Module Variables
  "terraform/modules/aws-sovereign/variables.tf"

  # Step 2F - Module Outputs
  "terraform/modules/aws-sovereign/outputs.tf"

  # Placeholder directories (should have at least empty dirs)
  "terraform/main.tf"
  "terraform/modules/azure-allied/.gitkeep"
  "terraform/modules/cross-cloud-vpn/.gitkeep"
  "terraform/modules/edge-simulator/.gitkeep"
  "terraform/environments/dev/.gitkeep"
  "terraform/environments/staging/.gitkeep"
  "terraform/environments/prod/.gitkeep"
  "ansible/playbooks/harden-nodes.yml"
  "ansible/playbooks/deploy-monitoring.yml"
  "ansible/playbooks/configure-vpn.yml"
  "kubernetes/base/deployment.yml"
  "kubernetes/base/service.yml"
  "kubernetes/base/network-policy.yml"
  "edge-app/Dockerfile"
  "edge-app/app.py"
  "edge-app/requirements.txt"
  "security/tfsec-config.yml"
  "security/checkov-config.yml"
  "security/opa-policies/.gitkeep"
  "tests/infra-tests/.gitkeep"
  "tests/integration-tests/.gitkeep"
  "docs/architecture.md"
  "docs/security-controls.md"
  "docs/runbook.md"
)

PASS=0
FAIL=0

for file in "${FILES[@]}"; do
  if [ -f "$file" ]; then
    echo "  ✅ $file"
    ((PASS++))
  else
    echo "  ❌ MISSING: $file"
    ((FAIL++))
  fi
done

echo ""
echo "=== Results ==="
echo "  ✅ Found: $PASS"
echo "  ❌ Missing: $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
  echo "🎉 All files present! Ready to commit and move to Step 3."
else
  echo "⚠️  Create the missing files above before proceeding."
fi


