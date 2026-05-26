# ═══════════════════════════════════════════════════════════════════════════════
# AWS SOVEREIGN MODULE — Input Variables
# ═══════════════════════════════════════════════════════════════════════════════

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.30"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS nodes"
  type        = string
  default     = "t3.medium"
}

variable "eks_node_min_size" {
  description = "Minimum number of EKS nodes"
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "Maximum number of EKS nodes"
  type        = number
  default     = 5
}

variable "eks_node_desired_size" {
  description = "Desired number of EKS nodes"
  type        = number
  default     = 2
}

variable "kms_key_arn" {
  description = "ARN of the KMS key (used internally, passed between resources)"
  type        = string
  default     = ""
}

variable "azure_vnet_cidr" {
  description = "CIDR of the Azure VNet (for NACLs and security group rules)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
