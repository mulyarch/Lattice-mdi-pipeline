# ═══════════════════════════════════════════════════════════════════════════════
# S3 — Encrypted Mission Data Storage
# Simulates classified data lake for edge telemetry and mission outputs
# All access via VPC endpoint only (no internet path)
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# MISSION DATA BUCKET
# ─────────────────────────────────────────────

resource "aws_s3_bucket" "mission_data" {
  bucket = "${var.project_name}-${var.environment}-mission-data-${data.aws_caller_identity.current.account_id}"

  # Prevent accidental deletion of mission data
  force_destroy = false

  tags = {
    Name           = "${var.project_name}-${var.environment}-mission-data"
    Classification = "SENSITIVE"
    DataType       = "mission-telemetry"
  }
}

# ─────────────────────────────────────────────
# ENCRYPTION — SSE-KMS with customer-managed key
# ─────────────────────────────────────────────

resource "aws_s3_bucket_server_side_encryption_configuration" "mission_data" {
  bucket = aws_s3_bucket.mission_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.sovereign.arn
    }
    bucket_key_enabled = true  # Reduces KMS API calls
  }
}

# ─────────────────────────────────────────────
# VERSIONING — Protect against accidental overwrites
# ─────────────────────────────────────────────

resource "aws_s3_bucket_versioning" "mission_data" {
  bucket = aws_s3_bucket.mission_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ─────────────────────────────────────────────
# BLOCK ALL PUBLIC ACCESS — Non-negotiable for sovereign
# ─────────────────────────────────────────────

resource "aws_s3_bucket_public_access_block" "mission_data" {
  bucket = aws_s3_bucket.mission_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─────────────────────────────────────────────
# BUCKET POLICY — VPC Endpoint access only
# Denies any request NOT from our VPC endpoint
# ─────────────────────────────────────────────

resource "aws_s3_bucket_policy" "mission_data" {
  bucket = aws_s3_bucket.mission_data.id

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

    # Keep non-current versions for 30 days (recovery window)
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ─────────────────────────────────────────────
# ACCESS LOGGING — Audit trail for all bucket access
# ─────────────────────────────────────────────

resource "aws_s3_bucket" "access_logs" {
  bucket = "${var.project_name}-${var.environment}-access-logs-${data.aws_caller_identity.current.account_id}"

  force_destroy = true

  tags = {
    Name    = "${var.project_name}-${var.environment}-access-logs"
    Purpose = "s3-access-logging"
  }
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
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.sovereign.arn
    }
  }
}

resource "aws_s3_bucket_logging" "mission_data" {
  bucket = aws_s3_bucket.mission_data.id

  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "mission-data-logs/"
}