# ═══════════════════════════════════════════════════════════════════════════════
# ROOT VARIABLES — Sovereign Multi-Cloud Infrastructure
# These are the top-level inputs passed to child modules
# Values come from terraform.tfvars (per environment) or CI/CD variables
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# GENERAL
# ─────────────────────────────────────────────

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "mdi-sovereign"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# ─────────────────────────────────────────────
# AWS CONFIGURATION
# ─────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region for sovereign environment"
  type        = string
  default     = "us-east-1"
}

variable "aws_vpc_cidr" {
  description = "CIDR block for the AWS sovereign VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.aws_vpc_cidr, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "aws_availability_zones" {
  description = "List of availability zones for the AWS VPC"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "aws_bgp_asn" {
  description = "BGP ASN for AWS VPN Gateway"
  type        = number
  default     = 64512
}

# ─────────────────────────────────────────────
# AWS EKS CONFIGURATION
# ─────────────────────────────────────────────

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.30"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "eks_node_min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 5
}

variable "eks_node_desired_size" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2
}

# ─────────────────────────────────────────────
# AZURE CONFIGURATION
# ─────────────────────────────────────────────

variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "azure_region" {
  description = "Azure region for allied environment"
  type        = string
  default     = "australiaeast"
}

variable "azure_vnet_cidr" {
  description = "CIDR block for the Azure allied VNet"
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrhost(var.azure_vnet_cidr, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "azure_bgp_asn" {
  description = "BGP ASN for Azure VPN Gateway"
  type        = number
  default     = 65515
}

# ─────────────────────────────────────────────
# AZURE AKS CONFIGURATION
# ─────────────────────────────────────────────

variable "aks_kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.30"
}

variable "aks_node_vm_size" {
  description = "VM size for AKS worker nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "aks_node_min_count" {
  description = "Minimum number of AKS worker nodes"
  type        = number
  default     = 2
}

variable "aks_node_max_count" {
  description = "Maximum number of AKS worker nodes"
  type        = number
  default     = 5
}

# ─────────────────────────────────────────────
# VPN CONFIGURATION
# ─────────────────────────────────────────────

variable "vpn_preshared_key_tunnel1" {
  description = "Pre-shared key for VPN tunnel 1 (min 32 characters)"
  type        = string
  sensitive   = true
  default     = "REPLACE_WITH_SECURE_KEY_MIN_32_CHARS_LONG_1"

  validation {
    condition     = length(var.vpn_preshared_key_tunnel1) >= 32
    error_message = "Pre-shared key must be at least 32 characters."
  }
}

variable "vpn_preshared_key_tunnel2" {
  description = "Pre-shared key for VPN tunnel 2 (min 32 characters)"
  type        = string
  sensitive   = true
  default     = "REPLACE_WITH_SECURE_KEY_MIN_32_CHARS_LONG_2"

  validation {
    condition     = length(var.vpn_preshared_key_tunnel2) >= 32
    error_message = "Pre-shared key must be at least 32 characters."
  }
}
