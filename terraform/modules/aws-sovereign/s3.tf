
# ═══════════════════════════════════════════════════════════════════════════════
# S3 — Encrypted Mission Data Storage
# AES-256 KMS encryption, VPC endpoint access, lifecycle policies
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# MISSION DATA BUCKET
# ─────────────────────────────────────────────

resource "aws_s3_bucket" "mission_data" {
  bucket = "${var.project_name}-${var.environment}-data-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-mission-data"
    DataClass   = "SOVEREIGN"
    Encryption  = "KMS-CMK"
    Compliance  = "IL5"
  })
}

# ─────────────────────────────────────────────
# ENCRYPTION — KMS Server-Side Encryption
# ─────────────────────────────────────────────

resource "aws_s3_bucket_server_side_encryption_configuration" "mission_data" {
  bucket = aws_s3_bucket.mission_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.sovereign.arn
    }
    bucket_key_enabled = true
  }
}

# ─────────────────────────────────────────────
# VERSIONING — Protect against accidental deletion
# ─────────────────────────────────────────────

resource "aws_s3_bucket_versioning" "mission_data" {
  bucket = aws_s3_bucket.mission_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ─────────────────────────────────────────────
# PUBLIC ACCESS BLOCK — No public access ever
# ─────────────────────────────────────────────

resource "aws_s3_bucket_public_access_block" "mission_data" {
  bucket = aws_s3_bucket.mission_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─────────────────────────────────────────────
# BUCKET POLICY — VPC Endpoint + TLS + KMS enforcement
# Allows terraform-user to manage the bucket from outside VPC
# ─────────────────────────────────────────────

resource "aws_s3_bucket_policy" "mission_data" {
  bucket = aws_s3_bucket.mission_data.id

  # Ensure public access block is applied first
  depends_on = [aws_s3_bucket_public_access_block.mission_data]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonVPCEndpointAccess"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.mission_data.arn,
          "${aws_s3_bucket.mission_data.arn}/*"
        ]
        Condition = {
          StringNotEquals = {
            "aws:sourceVpce" = aws_vpc_endpoint.s3.id
          }
          ArnNotEquals = {
            "aws:PrincipalArn" = [
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/terraform-user",
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
            ]
          }
        }
      },
      {
        Sid       = "EnforceTLSOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.mission_data.arn,
          "${aws_s3_bucket.mission_data.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "EnforceKMSEncryption"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.mission_data.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      }
    ]
  })
}

# ─────────────────────────────────────────────
# LIFECYCLE RULES — Data retention policy
# ─────────────────────────────────────────────

resource "aws_s3_bucket_lifecycle_configuration" "mission_data" {
  bucket = aws_s3_bucket.mission_data.id

  rule {
    filter {}
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }

  rule {
    filter {}
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ─────────────────────────────────────────────
# ACCESS LOGS BUCKET
# ─────────────────────────────────────────────

resource "aws_s3_bucket" "access_logs" {
  bucket = "${var.project_name}-${var.environment}-access-logs-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, {
    Name     = "${var.project_name}-${var.environment}-access-logs"
    Purpose  = "S3 access logging"
  })
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    filter {}
    id     = "expire-old-logs"
    status = "Enabled"

    expiration {
      days = 90
    }
  }
}

# ─────────────────────────────────────────────
# ACCESS LOGGING — Mission data → Logs bucket
# ─────────────────────────────────────────────

resource "aws_s3_bucket_logging" "mission_data" {
  bucket = aws_s3_bucket.mission_data.id

  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "mission-data-logs/"
}
