# Temporary AWS-only deployment file
# Remove this once Azure subscription is ready

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "anduril-mdi-pipeline"
    Owner       = "yuriy"
  }
  aws_account_id = data.aws_caller_identity.current.account_id
}

module "aws_sovereign" {
  source = "./modules/aws-sovereign"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  vpc_cidr           = var.aws_vpc_cidr
  availability_zones = var.aws_availability_zones
  azure_vnet_cidr    = var.azure_vnet_cidr

  eks_cluster_version    = var.eks_cluster_version
  eks_node_instance_type = var.eks_node_instance_type
  eks_node_min_size      = var.eks_node_min_size
  eks_node_max_size      = var.eks_node_max_size
  eks_node_desired_size  = var.eks_node_desired_size

  tags = local.common_tags
}
