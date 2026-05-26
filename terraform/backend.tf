# ═══════════════════════════════════════════════════════════════════════════════
# BACKEND — Remote State Storage
# S3 backend with DynamoDB locking for team collaboration
# State is encrypted at rest with KMS
# ═══════════════════════════════════════════════════════════════════════════════

terraform {
  backend "s3" {
    bucket         = "aws-terraform-state-bucket-0011"
    key            = "sovereign-infra/terraform.tfstate"  # Overridden per environment in CI/CD
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"

    # Uncomment for KMS encryption of state file
    # kms_key_id = "alias/terraform-state-key"
  }
}
