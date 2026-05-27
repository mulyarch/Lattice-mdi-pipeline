# ═══════════════════════════════════════════════════════════════════════════════
# ROOT OUTPUTS — AWS Sovereign Only (Azure added later)
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# AWS SOVEREIGN OUTPUTS
# ─────────────────────────────────────────────

output "aws_vpc_id" {
  description = "ID of the AWS sovereign VPC"
  value       = module.aws_sovereign.vpc_id
}

output "aws_vpc_cidr" {
  description = "CIDR of the AWS sovereign VPC"
  value       = var.aws_vpc_cidr
}

output "aws_eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.aws_sovereign.eks_cluster_name
}

output "aws_eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.aws_sovereign.eks_cluster_endpoint
  sensitive   = true
}

output "aws_eks_cluster_version" {
  description = "EKS cluster Kubernetes version"
  value       = module.aws_sovereign.eks_cluster_version
}

output "aws_s3_bucket_name" {
  description = "Name of the encrypted mission data S3 bucket"
  value       = module.aws_sovereign.s3_bucket_name
}

output "aws_kms_key_arn" {
  description = "ARN of the KMS key for data encryption"
  value       = module.aws_sovereign.kms_key_arn
  sensitive   = true
}

output "deployment_summary" {
  description = "Deployment summary"
  value = {
    project     = var.project_name
    environment = var.environment

    aws = {
      region      = var.aws_region
      vpc_cidr    = var.aws_vpc_cidr
      eks_cluster = module.aws_sovereign.eks_cluster_name
      eks_version = module.aws_sovereign.eks_cluster_version
    }

    security = {
      encryption_at_rest    = "KMS"
      encryption_in_transit = "TLS 1.2+"
      network_isolation     = "Private subnets + NACLs + Security Groups"
      identity              = "IRSA (IAM Roles for Service Accounts)"
      monitoring            = "GuardDuty + CloudWatch"
    }
  }
}

