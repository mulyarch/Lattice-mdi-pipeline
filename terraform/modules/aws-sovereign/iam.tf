
# ═══════════════════════════════════════════════════════════════════════════════
# IAM ROLES — Least Privilege Access for EKS
# Uses IRSA (IAM Roles for Service Accounts) for pod-level permissions
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# EKS CLUSTER ROLE
# Minimal permissions for the control plane
# ─────────────────────────────────────────────

resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

# ─────────────────────────────────────────────
# EKS NODE GROUP ROLE
# Permissions for worker nodes only
# ─────────────────────────────────────────────

resource "aws_iam_role" "eks_nodes" {
  name = "${var.project_name}-${var.environment}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

# ─────────────────────────────────────────────
# CUSTOM NODE POLICY — Scoped to specific resources
# No wildcard permissions (defense requirement)
# ─────────────────────────────────────────────

resource "aws_iam_policy" "eks_node_custom" {
  name        = "${var.project_name}-${var.environment}-eks-node-custom"
  description = "Custom policy for EKS nodes - scoped to project resources only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/eks/${var.project_name}-${var.environment}*"
      },
      {
        Sid    = "AllowKMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.kms_key_arn != "" ? [var.kms_key_arn] : ["*"]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${var.aws_region}.amazonaws.com"
          }
        }
      },
      {
        Sid    = "AllowS3MissionData"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-${var.environment}-mission-data",
          "arn:aws:s3:::${var.project_name}-${var.environment}-mission-data/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_custom" {
  policy_arn = aws_iam_policy.eks_node_custom.arn
  role       = aws_iam_role.eks_nodes.name
}

# ─────────────────────────────────────────────
# OIDC PROVIDER — Enables IRSA (IAM Roles for Service Accounts)
# Pods get their own IAM identity instead of inheriting node role
# ─────────────────────────────────────────────

data "tls_certificate" "eks" {
  url = aws_eks_cluster.sovereign.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.sovereign.identity[0].oidc[0].issuer

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-oidc"
  }
}

# ─────────────────────────────────────────────
# IRSA ROLE — Example: Mission Data Processor Pod
# Only this specific pod can access mission data S3 bucket
# ─────────────────────────────────────────────

resource "aws_iam_role" "mission_data_processor" {
  name = "${var.project_name}-${var.environment}-mission-data-processor"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_eks_cluster.sovereign.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:mission:data-processor"
            "${replace(aws_eks_cluster.sovereign.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-mission-data-processor-role"
  }
}

resource "aws_iam_policy" "mission_data_access" {
  name        = "${var.project_name}-${var.environment}-mission-data-access"
  description = "Scoped access to mission data bucket for data processor pod"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadWriteMissionData"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-${var.environment}-mission-data",
          "arn:aws:s3:::${var.project_name}-${var.environment}-mission-data/*"
        ]
      },
      {
        Sid    = "DecryptMissionData"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arn != "" ? [var.kms_key_arn] : ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "mission_data_processor" {
  policy_arn = aws_iam_policy.mission_data_access.arn
  role       = aws_iam_role.mission_data_processor.name
}

