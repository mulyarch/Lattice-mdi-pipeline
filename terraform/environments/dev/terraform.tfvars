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
azure_subscription_id = "6c33a25e-2c42-4d6e-a8b5-914d12fe01d3"
