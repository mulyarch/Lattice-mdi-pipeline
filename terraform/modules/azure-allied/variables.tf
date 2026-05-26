# ─────────────────────────────────────────────
# Azure Allied Module Variables
# ─────────────────────────────────────────────

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "azure_region" {
  description = "Azure region for allied deployment"
  type        = string
  default     = "australiaeast"
}

variable "vnet_cidr" {
  description = "CIDR block for the allied VNet"
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrhost(var.vnet_cidr, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "aws_vpc_cidr" {
  description = "AWS VPC CIDR for cross-cloud NSG rules"
  type        = string
  default     = "10.0.0.0/16"
}

# ─────────────────────────────────────────────
# AKS Variables
# ─────────────────────────────────────────────

variable "aks_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.29"
}

variable "aks_system_vm_size" {
  description = "VM size for AKS system node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "aks_system_node_count" {
  description = "Initial node count for system pool"
  type        = number
  default     = 2
}

variable "aks_mission_vm_size" {
  description = "VM size for AKS mission node pool"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "aks_mission_node_count" {
  description = "Initial node count for mission pool"
  type        = number
  default     = 2
}
