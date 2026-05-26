# ═══════════════════════════════════════════════════════════════════════════════
# KMS — Customer-Managed Encryption Keys
# Single key with scoped policy for all sovereign resources
# Mirrors IL5/IL6 requirement: all data encrypted with org-controlled keys
# ═══════════════════════════════════════════════════════════════════════════════

# Use the module-level data source (don't redeclare)
# data "aws_caller_identity" "current" {} is in main.tf of this module

resource "aws_kms_key" "sovereign" {
  description             = "CMK for ${var.project_name}-${var.environment} sovereign infrastructure"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  multi_region            = false

  # Start with a permissive policy — tighten after all resources are created
  # This avoids circular dependencies with IAM roles
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${var.project_name}-${var.environment}-key-policy"
    Statement = [
      {
        Sid    = "EnableRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowEKSService"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      },
      {
        Sid    = "AllowS3Service"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowAccountRoles"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey",
          "kms:Encrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-sovereign-cmk"
  })
}

resource "aws_kms_alias" "sovereign" {
  name          = "alias/${var.project_name}-${var.environment}-sovereign"
  target_key_id = aws_kms_key.sovereign.key_id
}
