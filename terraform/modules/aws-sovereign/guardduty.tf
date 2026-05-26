# ═══════════════════════════════════════════════════════════════════════════════
# GUARDDUTY — Continuous Threat Detection
# Monitors for malicious activity and unauthorized behavior
# Required for defense/classified environments
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_guardduty_detector" "sovereign" {
  enable = true

  # S3 protection — detect anomalous data access patterns
  datasources {
    s3_logs {
      enable = true
    }

    kubernetes {
      audit_logs {
        enable = true
      }
    }

    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  # Publish findings every 15 minutes (fastest interval)
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = {
    Name = "${var.project_name}-${var.environment}-guardduty"
  }
}

# ─────────────────────────────────────────────
# SNS TOPIC — Alert on high-severity findings
# ─────────────────────────────────────────────

resource "aws_sns_topic" "security_alerts" {
  name              = "${var.project_name}-${var.environment}-security-alerts"
  kms_master_key_id = aws_kms_key.sovereign.id

  tags = {
    Name = "${var.project_name}-${var.environment}-security-alerts"
  }
}

resource "aws_sns_topic_policy" "security_alerts" {
  arn = aws_sns_topic.security_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.security_alerts.arn
      }
    ]
  })
}

# ─────────────────────────────────────────────
# EVENTBRIDGE RULE — Route high-severity findings to SNS
# ─────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "guardduty_high_severity" {
  name        = "${var.project_name}-${var.environment}-guardduty-high"
  description = "Capture high-severity GuardDuty findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-guardduty-high-rule"
  }
}

resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_high_severity.name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.security_alerts.arn
}