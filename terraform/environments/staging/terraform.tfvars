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
