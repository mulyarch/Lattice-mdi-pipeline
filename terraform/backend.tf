# ═══════════════════════════════════════════════════════════════════════════════
# BACKEND — Remote State Storage
# S3 backend with DynamoDB locking for team collaboration
# State is encrypted at rest
# ═══════════════════════════════════════════════════════════════════════════════

terraform {
  backend "s3" {
    bucket       = "aws-terraform-state-bucket-0011"
    key          = "anduril-mdi-pipeline/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

