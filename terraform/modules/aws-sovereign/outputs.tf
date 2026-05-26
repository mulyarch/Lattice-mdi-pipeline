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
