# ═══════════════════════════════════════════════════════════════════════════════
# AZURE ALLIED MODULE — Input Variables
# ═══════════════════════════════════════════════════════════════════════════════

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "azure_region" {
  description = "Azure region"
  type        = string
}

variable "vnet_cidr" {
  description = "CIDR block for the VNet"
  type        = string
}

variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "aks_kubernetes_version" {
  description = "Kubernetes version for AKS (passed from root)"
  type        = string
  default     = "1.29"
}

variable "aks_version" {
  description = "Kubernetes version for AKS (used in aks.tf)"
  type        = string
  default     = "1.29"
}

variable "aks_node_vm_size" {
  description = "VM size for AKS worker nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "aks_system_vm_size" {
  description = "VM size for AKS system node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "aks_node_min_count" {
  description = "Minimum number of AKS nodes"
  type        = number
  default     = 2
}

variable "aks_node_max_count" {
  description = "Maximum number of AKS nodes"
  type        = number
  default     = 5
}

variable "aks_system_node_count" {
  description = "Number of nodes in the AKS system pool"
  type        = number
  default     = 2
}

variable "aws_vpc_cidr" {
  description = "CIDR of the AWS VPC (for NSG rules allowing cross-cloud traffic)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "aks_mission_vm_size" {
  description = "VM size for AKS mission-critical node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "aks_mission_node_count" {
  description = "Number of nodes in the AKS mission node pool"
  type        = number
  default     = 2
}
