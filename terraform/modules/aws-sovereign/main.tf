data "aws_caller_identity" "current" {}
# ═══════════════════════════════════════════════════════════════════════════════
# AWS SOVEREIGN VPC MODULE
# Simulates an IL5/IL6 isolated environment for classified workloads
# Design principles: Zero trust, no public endpoints, encryption everywhere
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# VPC — Isolated network boundary
# ─────────────────────────────────────────────

resource "aws_vpc" "sovereign" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  # Required for EKS
  tags = {
    Name = "${var.project_name}-${var.environment}-sovereign-vpc"
    "kubernetes.io/cluster/${var.project_name}-${var.environment}" = "shared"
  }
}

# ─────────────────────────────────────────────
# PRIVATE SUBNETS — No public IPs, no internet
# Three AZs for high availability
# ─────────────────────────────────────────────

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.sovereign.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone = var.availability_zones[count.index]

  # CRITICAL: No public IPs in sovereign environment
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-${var.environment}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/cluster/${var.project_name}-${var.environment}" = "shared"
    "kubernetes.io/role/internal-elb" = "1"
    Tier = "private"
  }
}

# ─────────────────────────────────────────────
# INTRA SUBNETS — For VPN endpoints and 
# cross-cloud connectivity (isolated from app tier)
# ─────────────────────────────────────────────

resource "aws_subnet" "intra" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.sovereign.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 4)
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-${var.environment}-intra-${var.availability_zones[count.index]}"
    Tier = "intra"
  }
}

# ─────────────────────────────────────────────
# ROUTE TABLES — Isolated routing, no IGW
# ─────────────────────────────────────────────

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.sovereign.id

  tags = {
    Name = "${var.project_name}-${var.environment}-private-rt"
  }
}

resource "aws_route_table" "intra" {
  vpc_id = aws_vpc.sovereign.id

  tags = {
    Name = "${var.project_name}-${var.environment}-intra-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "intra" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.intra[count.index].id
  route_table_id = aws_route_table.intra.id
}

# ─────────────────────────────────────────────
# NETWORK ACLs — Stateless packet filtering
# Defense-in-depth layer beyond security groups
# ─────────────────────────────────────────────

resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.sovereign.id
  subnet_ids = aws_subnet.private[*].id

  # Allow intra-VPC traffic
  ingress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  # Allow traffic from Azure allied VNet (cross-cloud VPN)
  ingress {
    protocol   = -1
    rule_no    = 200
    action     = "allow"
    cidr_block = var.azure_vnet_cidr
    from_port  = 0
    to_port    = 0
  }

  # Allow ephemeral ports for return traffic
  ingress {
    protocol   = "tcp"
    rule_no    = 300
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Deny all other inbound
  ingress {
    protocol   = -1
    rule_no    = 999
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  # Allow outbound to VPC and Azure
  egress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = -1
    rule_no    = 200
    action     = "allow"
    cidr_block = var.azure_vnet_cidr
    from_port  = 0
    to_port    = 0
  }

  # Allow HTTPS out for AWS API calls (via VPC endpoints)
  egress {
    protocol   = "tcp"
    rule_no    = 300
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  egress {
    protocol   = -1
    rule_no    = 999
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-private-nacl"
  }
}

# ─────────────────────────────────────────────
# SECURITY GROUPS — Stateful, least-privilege
# ─────────────────────────────────────────────

# EKS Cluster Security Group
resource "aws_security_group" "eks_cluster" {
  name_prefix = "${var.project_name}-${var.environment}-eks-cluster-"
  vpc_id      = aws_vpc.sovereign.id
  description = "Security group for EKS control plane"

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-cluster-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# EKS Worker Nodes Security Group
resource "aws_security_group" "eks_workers" {
  name_prefix = "${var.project_name}-${var.environment}-eks-workers-"
  vpc_id      = aws_vpc.sovereign.id
  description = "Security group for EKS worker nodes"

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-workers-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Worker-to-Cluster communication
resource "aws_security_group_rule" "workers_to_cluster" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster.id
  source_security_group_id = aws_security_group.eks_workers.id
  description              = "Worker nodes to cluster API"
}

# Cluster-to-Worker communication
resource "aws_security_group_rule" "cluster_to_workers" {
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_workers.id
  source_security_group_id = aws_security_group.eks_cluster.id
  description              = "Cluster to worker nodes"
}

# Worker-to-Worker communication (pod networking)
resource "aws_security_group_rule" "workers_internal" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.eks_workers.id
  self              = true
  description       = "Worker node inter-communication"
}

# Allow traffic from Azure VNet (cross-cloud)
resource "aws_security_group_rule" "from_azure" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.eks_workers.id
  cidr_blocks       = [var.azure_vnet_cidr]
  description       = "Inbound from Azure allied VNet via VPN"
}

# ─────────────────────────────────────────────
# VPC ENDPOINTS — Private access to AWS services
# No internet gateway needed (sovereign pattern)
# ─────────────────────────────────────────────

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.sovereign.id
  service_name = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [aws_route_table.private.id]

  tags = {
    Name = "${var.project_name}-${var.environment}-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.sovereign.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-${var.environment}-ecr-api-endpoint"
  }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.sovereign.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-${var.environment}-ecr-dkr-endpoint"
  }
}

resource "aws_vpc_endpoint" "sts" {
  vpc_id              = aws_vpc.sovereign.id
  service_name        = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-${var.environment}-sts-endpoint"
  }
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.sovereign.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-${var.environment}-logs-endpoint"
  }
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.project_name}-${var.environment}-vpce-"
  vpc_id      = aws_vpc.sovereign.id
  description = "Security group for VPC endpoints"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS from VPC"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-vpce-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────
# VPC FLOW LOGS — Full packet metadata capture
# Required for compliance and incident response
# ─────────────────────────────────────────────

resource "aws_flow_log" "sovereign" {
  vpc_id                   = aws_vpc.sovereign.id
  traffic_type             = "ALL"
  iam_role_arn             = aws_iam_role.flow_log.arn
  log_destination          = aws_cloudwatch_log_group.flow_log.arn
  max_aggregation_interval = 60

  tags = {
    Name = "${var.project_name}-${var.environment}-flow-log"
  }
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc/flow-log/${var.project_name}-${var.environment}"
  retention_in_days = 90
  kms_key_id        = var.kms_key_arn

  tags = {
    Name = "${var.project_name}-${var.environment}-flow-log-group"
  }
}

resource "aws_iam_role" "flow_log" {
  name = "${var.project_name}-${var.environment}-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "flow_log" {
  name = "${var.project_name}-${var.environment}-flow-log-policy"
  role = aws_iam_role.flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}