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


**Step 2F — Module Outputs**

```python
```hcl

output "vpc_id" {
  description = "ID of the sovereign VPC"
  value       = aws_vpc.sovereign.id
}

output "vpc_cidr" {
  description = "CIDR block of the sovereign VPC"
  value       = aws_vpc.sovereign.cidr_block
}

output "private_subnet_ids" {
  description = "IDs of private subnets (for EKS workers)"
  value       = aws_subnet.private[*].id
}

output "intra_subnet_ids" {
  description = "IDs of intra subnets (for VPN endpoints)"
  value       = aws_subnet.intra[*].id
}

output "eks_cluster_sg_id" {
  description = "Security group ID for EKS cluster"
  value       = aws_security_group.eks_cluster.id
}

output "eks_workers_sg_id" {
  description = "Security group ID for EKS worker nodes"
  value       = aws_security_group.eks_workers.id
}

output "private_route_table_id" {
  description = "Route table ID for private subnets"
  value       = aws_route_table.private.id
}

output "intra_route_table_id" {
  description = "Route table ID for intra subnets"
  value       = aws_route_table.intra.id
}