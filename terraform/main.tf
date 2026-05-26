# Root Module - Anduril MDI Sovereign Infrastructure

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

module "azure_allied" {
  source = "./modules/azure-allied"

  project_name          = var.project_name
  environment           = var.environment
  azure_region          = var.azure_region
  vnet_cidr             = var.azure_vnet_cidr
  azure_subscription_id = var.azure_subscription_id
  aws_vpc_cidr          = var.aws_vpc_cidr

  aks_kubernetes_version = var.aks_kubernetes_version
  aks_version            = var.aks_kubernetes_version
  aks_node_vm_size       = var.aks_node_vm_size
  aks_system_vm_size     = var.aks_node_vm_size
  aks_node_min_count     = var.aks_node_min_count
  aks_node_max_count     = var.aks_node_max_count
  aks_system_node_count  = var.aks_node_min_count

  tags = local.common_tags
}

module "cross_cloud_vpn" {
  source = "./modules/cross-cloud-vpn"

  project_name = var.project_name
  environment  = var.environment

  aws_vpc_id                 = module.aws_sovereign.vpc_id
  aws_vpc_cidr               = var.aws_vpc_cidr
  aws_private_route_table_id = module.aws_sovereign.private_route_table_id
  aws_intra_route_table_id   = module.aws_sovereign.intra_route_table_id
  aws_bgp_asn                = var.aws_bgp_asn
  aws_sns_topic_arn          = module.aws_sovereign.sns_topic_arn

  azure_region                     = var.azure_region
  azure_resource_group_name        = module.azure_allied.resource_group_name
  azure_gateway_subnet_id          = module.azure_allied.gateway_subnet_id
  azure_vnet_cidr                  = var.azure_vnet_cidr
  azure_bgp_asn                    = var.azure_bgp_asn
  azure_log_analytics_workspace_id = module.azure_allied.log_analytics_workspace_id

  vpn_preshared_key_tunnel1 = var.vpn_preshared_key_tunnel1
  vpn_preshared_key_tunnel2 = var.vpn_preshared_key_tunnel2
}
