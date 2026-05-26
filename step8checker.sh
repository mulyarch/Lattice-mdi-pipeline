#!/bin/bash
echo "=== Step 8 File Verification ==="
echo ""

FILES=(
  ".github/workflows/deploy-infra.yml"
  ".github/workflows/deploy-app.yml"
  ".github/workflows/configure.yml"
  "terraform/environments/dev/terraform.tfvars"
  "terraform/environments/staging/terraform.tfvars"
  "terraform/environments/prod/terraform.tfvars"
)

PASS=0
FAIL=0

for f in "${FILES[@]}"; do
  if [ -f "$f" ]; then
    echo "  ✅ $f"
    ((PASS++))
  else
    echo "  ❌ $f (MISSING)"
    ((FAIL++))
  fi
done

echo ""
echo "=== Content Verification ==="
echo ""

# Check deploy-infra.yml has key sections
if [ -f ".github/workflows/deploy-infra.yml" ]; then
  echo "── deploy-infra.yml ──"
  grep -q "preflight" .github/workflows/deploy-infra.yml && echo "  ✅ Has preflight stage" || echo "  ❌ Missing preflight stage"
  grep -q "Terraform Plan" .github/workflows/deploy-infra.yml && echo "  ✅ Has plan stage" || echo "  ❌ Missing plan stage"
  grep -q "security-review" .github/workflows/deploy-infra.yml && echo "  ✅ Has security review stage" || echo "  ❌ Missing security review stage"
  grep -q "approve" .github/workflows/deploy-infra.yml && echo "  ✅ Has approval gate" || echo "  ❌ Missing approval gate"
  grep -q "Terraform Apply" .github/workflows/deploy-infra.yml && echo "  ✅ Has apply stage" || echo "  ❌ Missing apply stage"
  grep -q "destroy" .github/workflows/deploy-infra.yml && echo "  ✅ Has destroy stage" || echo "  ❌ Missing destroy stage"
  grep -q "OIDC" .github/workflows/deploy-infra.yml && echo "  ✅ Has OIDC auth" || echo "  ❌ Missing OIDC auth"
  grep -q "concurrency" .github/workflows/deploy-infra.yml && echo "  ✅ Has concurrency lock" || echo "  ❌ Missing concurrency lock"
fi

echo ""

# Check deploy-app.yml has key sections
if [ -f ".github/workflows/deploy-app.yml" ]; then
  echo "── deploy-app.yml ──"
  grep -q "Build Container" .github/workflows/deploy-app.yml && echo "  ✅ Has build stage" || echo "  ❌ Missing build stage"
  grep -q "deploy-eks" .github/workflows/deploy-app.yml && echo "  ✅ Has EKS deploy" || echo "  ❌ Missing EKS deploy"
  grep -q "deploy-aks" .github/workflows/deploy-app.yml && echo "  ✅ Has AKS deploy" || echo "  ❌ Missing AKS deploy"
  grep -q "integration-test" .github/workflows/deploy-app.yml && echo "  ✅ Has integration test" || echo "  ❌ Missing integration test"
  grep -q "trivy" .github/workflows/deploy-app.yml && echo "  ✅ Has Trivy scan" || echo "  ❌ Missing Trivy scan"
fi

echo ""

# Check configure.yml has key sections
if [ -f ".github/workflows/configure.yml" ]; then
  echo "── configure.yml ──"
  grep -q "Ansible" .github/workflows/configure.yml && echo "  ✅ Has Ansible" || echo "  ❌ Missing Ansible"
  grep -q "harden-nodes" .github/workflows/configure.yml && echo "  ✅ Has harden-nodes" || echo "  ❌ Missing harden-nodes"
  grep -q "deploy-monitoring" .github/workflows/configure.yml && echo "  ✅ Has deploy-monitoring" || echo "  ❌ Missing deploy-monitoring"
  grep -q "configure-vpn" .github/workflows/configure.yml && echo "  ✅ Has configure-vpn" || echo "  ❌ Missing configure-vpn"
fi

echo ""

# Check tfvars files have content
if [ -f "terraform/environments/dev/terraform.tfvars" ]; then
  echo "── terraform.tfvars files ──"
  grep -q 'environment = "dev"' terraform/environments/dev/terraform.tfvars && echo "  ✅ dev has correct env" || echo "  ❌ dev missing env"
  grep -q 'environment = "staging"' terraform/environments/staging/terraform.tfvars && echo "  ✅ staging has correct env" || echo "  ❌ staging missing env"
  grep -q 'environment = "prod"' terraform/environments/prod/terraform.tfvars && echo "  ✅ prod has correct env" || echo "  ❌ prod missing env"
fi

echo ""
echo "=== Results ==="
echo "  ✅ Found: $PASS"
echo "  ❌ Missing: $FAIL"

if [ $FAIL -eq 0 ]; then
  echo ""
  echo "🎉 Step 8 is complete! All files verified."
else
  echo ""
  echo "⚠️  Some files are missing. Re-run create_cd_files.sh to fix."
fi
