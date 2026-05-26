
#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Create GitHub Environments with Protection Rules via gh CLI
# Run from your repo directory (must be authenticated with `gh auth login`)
# ═══════════════════════════════════════════════════════════════════════════════

# Get repo info
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
echo "📦 Configuring environments for: $REPO"
echo ""

# Get your GitHub user ID (needed for reviewers)
MY_USER_ID=$(gh api /user --jq '.id')
MY_USERNAME=$(gh api /user --jq '.login')
echo "👤 Your username: $MY_USERNAME (ID: $MY_USER_ID)"
echo ""

# ─────────────────────────────────────────────
# DEV ENVIRONMENTS (no protection rules)
# ─────────────────────────────────────────────

echo "Creating dev environments..."

# dev-plan (no protection)
gh api --method PUT "repos/$REPO/environments/dev-plan" \
  --input - << EOF
{
  "deployment_branch_policy": null
}
EOF
echo "  ✅ dev-plan"

# dev-approve (no protection)
gh api --method PUT "repos/$REPO/environments/dev-approve" \
  --input - << EOF
{
  "deployment_branch_policy": null
}
EOF
echo "  ✅ dev-approve"

# dev (no protection)
gh api --method PUT "repos/$REPO/environments/dev" \
  --input - << EOF
{
  "deployment_branch_policy": null
}
EOF
echo "  ✅ dev"

# ─────────────────────────────────────────────
# STAGING ENVIRONMENTS (require your approval)
# ─────────────────────────────────────────────

echo ""
echo "Creating staging environments..."

# staging-plan (no protection)
gh api --method PUT "repos/$REPO/environments/staging-plan" \
  --input - << EOF
{
  "deployment_branch_policy": null
}
EOF
echo "  ✅ staging-plan"

# staging-approve (requires your approval)
gh api --method PUT "repos/$REPO/environments/staging-approve" \
  --input - << EOF
{
  "reviewers": [
    {
      "type": "User",
      "id": $MY_USER_ID
    }
  ],
  "deployment_branch_policy": null
}
EOF
echo "  ✅ staging-approve (reviewer: $MY_USERNAME)"

# staging (requires your approval)
gh api --method PUT "repos/$REPO/environments/staging" \
  --input - << EOF
{
  "reviewers": [
    {
      "type": "User",
      "id": $MY_USER_ID
    }
  ],
  "deployment_branch_policy": null
}
EOF
echo "  ✅ staging (reviewer: $MY_USERNAME)"

# ─────────────────────────────────────────────
# PROD ENVIRONMENTS (approval + wait timer)
# ─────────────────────────────────────────────

echo ""
echo "Creating prod environments..."

# prod-plan (no protection)
gh api --method PUT "repos/$REPO/environments/prod-plan" \
  --input - << EOF
{
  "deployment_branch_policy": null
}
EOF
echo "  ✅ prod-plan"

# prod-approve (approval + 5 min wait)
gh api --method PUT "repos/$REPO/environments/prod-approve" \
  --input - << EOF
{
  "wait_timer": 5,
  "reviewers": [
    {
      "type": "User",
      "id": $MY_USER_ID
    }
  ],
  "deployment_branch_policy": null
}
EOF
echo "  ✅ prod-approve (reviewer: $MY_USERNAME, wait: 5 min)"

# prod (approval + 5 min wait)
gh api --method PUT "repos/$REPO/environments/prod" \
  --input - << EOF
{
  "wait_timer": 5,
  "reviewers": [
    {
      "type": "User",
      "id": $MY_USER_ID
    }
  ],
  "deployment_branch_policy": null
}
EOF
echo "  ✅ prod (reviewer: $MY_USERNAME, wait: 5 min)"

# prod-destroy (approval + 15 min wait)
gh api --method PUT "repos/$REPO/environments/prod-destroy" \
  --input - << EOF
{
  "wait_timer": 15,
  "reviewers": [
    {
      "type": "User",
      "id": $MY_USER_ID
    }
  ],
  "deployment_branch_policy": null
}
EOF
echo "  ✅ prod-destroy (reviewer: $MY_USERNAME, wait: 15 min)"

# ─────────────────────────────────────────────
# VERIFY
# ─────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════"
echo "📋 Verifying all environments..."
echo "═══════════════════════════════════════════"
echo ""

gh api "repos/$REPO/environments" --jq '.environments[] | "  \(.name) — protection_rules: \(.protection_rules | length)"'

echo ""
echo "🎉 All environments configured!"
echo ""
echo "═══════════════════════════════════════════"
echo "Summary:"
echo "═══════════════════════════════════════════"
echo ""
echo "  Environment        | Approval | Wait Timer"
echo "  -------------------|----------|----------"
echo "  dev-plan           | None     | None"
echo "  dev-approve        | None     | None"
echo "  dev                | None     | None"
echo "  staging-plan       | None     | None"
echo "  staging-approve    | You      | None"
echo "  staging            | You      | None"
echo "  prod-plan          | None     | None"
echo "  prod-approve       | You      | 5 min"
echo "  prod               | You      | 5 min"
echo "  prod-destroy       | You      | 15 min"

