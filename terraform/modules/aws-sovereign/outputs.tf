# ═══════════════════════════════════════════════════════════════════════════════
# AWS SOVEREIGN MODULE — Outputs
# ═══════════════════════════════════════════════════════════════════════════════

output "vpc_id" {
  description = "ID of the sovereign VPC"
  value       = aws_vpc.sovereign.id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "intra_subnet_ids" {
  description = "IDs of intra subnets"
  value       = aws_subnet.intra[*].id
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = aws_route_table.private.id
}

output "intra_route_table_id" {
  description = "ID of the intra route table"
  value       = aws_route_table.intra.id
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.sovereign.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.sovereign.endpoint
}

output "eks_cluster_ca_certificate" {
  description = "EKS cluster CA certificate"
  value       = aws_eks_cluster.sovereign.certificate_authority[0].data
}

output "eks_cluster_version" {
  description = "EKS cluster Kubernetes version"
  value       = aws_eks_cluster.sovereign.version
}

output "s3_bucket_name" {
  description = "Name of the mission data S3 bucket"
  value       = aws_s3_bucket.mission_data.id
}

output "s3_bucket_arn" {
  description = "ARN of the mission data S3 bucket"
  value       = aws_s3_bucket.mission_data.arn
}

output "kms_key_arn" {
  description = "ARN of the sovereign KMS key"
  value       = aws_kms_key.sovereign.arn
}

output "kms_key_id" {
  description = "ID of the sovereign KMS key"
  value       = aws_kms_key.sovereign.id
}

output "sns_topic_arn" {
  description = "ARN of the security alerts SNS topic"
  value       = aws_sns_topic.security_alerts.arn
}

output "eks_node_role_arn" {
  description = "ARN of the EKS node IAM role"
  value       = aws_iam_role.eks_nodes.arn
}
