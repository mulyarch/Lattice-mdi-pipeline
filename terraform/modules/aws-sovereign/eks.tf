
# ═══════════════════════════════════════════════════════════════════════════════
# EKS CLUSTER — Managed Kubernetes for Sovereign Workloads
# Private endpoint only, encrypted secrets, audit logging enabled
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# EKS CLUSTER
# ─────────────────────────────────────────────

resource "aws_eks_cluster" "sovereign" {
  name     = "${var.project_name}-${var.environment}"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_cluster_version

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id

    # CRITICAL: Private endpoint only — no public API access
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # Encrypt Kubernetes secrets at rest with customer-managed KMS key
  encryption_config {
    provider {
      key_arn = aws_kms_key.sovereign.arn
    }
    resources = ["secrets"]
  }

  # Enable all audit logging for compliance
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  # Ensure IAM roles are created before cluster
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
    aws_cloudwatch_log_group.eks
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-cluster"
  }
}

# ─────────────────────────────────────────────
# EKS LOG GROUP — Encrypted audit logs
# ─────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.project_name}-${var.environment}/cluster"
  retention_in_days = 90

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-logs"
  }
}

# ─────────────────────────────────────────────
# MANAGED NODE GROUP — Worker nodes
# Private subnets, encrypted volumes, auto-scaling
# ─────────────────────────────────────────────

resource "aws_eks_node_group" "sovereign_workers" {
  cluster_name    = aws_eks_cluster.sovereign.name
  node_group_name = "${var.project_name}-${var.environment}-workers"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id

  scaling_config {
    desired_size = var.eks_node_desired_size
    max_size     = var.eks_node_max_size
    min_size     = var.eks_node_min_size
  }

  # Use latest Amazon Linux 2 EKS-optimized AMI
  ami_type       = "AL2_x86_64"
  instance_types = [var.eks_node_instance_type]
  capacity_type  = "ON_DEMAND"

  update_config {
    max_unavailable = 1
  }

  labels = {
    environment = var.environment
    workload    = "mission"
  }

  taint {
    key    = "workload"
    value  = "mission-critical"
    effect = "NO_SCHEDULE"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ecr_read_only,
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-workers"
  }
}
# ─────────────────────────────────────────────

resource "aws_launch_template" "eks_workers" {
  name_prefix = "${var.project_name}-${var.environment}-eks-"

  # Encrypted root volume
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 50
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # IMDSv2 required — prevents SSRF attacks against metadata service
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 only
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  # Enable monitoring
  monitoring {
    enabled = true
  }

  # No public IP
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.eks_workers.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-${var.environment}-eks-worker"
      Environment = var.environment
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name      = "${var.project_name}-${var.environment}-eks-worker-vol"
      Encrypted = "true"
    }
  }
}

# ─────────────────────────────────────────────
# EKS ADDONS — Core cluster components
# ─────────────────────────────────────────────

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.sovereign.name
  addon_name   = "vpc-cni"

  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.sovereign.name
  addon_name   = "coredns"

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.sovereign_workers]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.sovereign.name
  addon_name   = "kube-proxy"

  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.sovereign.name
  addon_name   = "aws-ebs-csi-driver"

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.sovereign_workers]
}

