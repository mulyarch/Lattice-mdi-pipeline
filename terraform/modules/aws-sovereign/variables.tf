variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the sovereign VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "availability_zones" {
  description = "List of AZs for multi-AZ deployment"
  type        = list(string)
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "azure_vnet_cidr" {
  description = "Azure VNet CIDR for cross-cloud NACL rules"
  type        = string
  default     = "10.1.0.0/16"
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting flow logs"
  type        = string
  default     = ""
}