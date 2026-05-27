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
