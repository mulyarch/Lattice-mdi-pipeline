"""
Application configuration — loaded from environment variables.
Follows 12-factor app methodology.
"""

import os
from dataclasses import dataclass


@dataclass
class Config:
    """Application configuration"""
    # Service
    service_name: str = "mission-data-processor"
    version: str = "1.0.0"
    environment: str = os.getenv("ENVIRONMENT", "dev")
    cloud_provider: str = os.getenv("CLOUD_PROVIDER", "aws")
    region: str = os.getenv("REGION", "us-east-1")
    log_level: str = os.getenv("LOG_LEVEL", "info")
    workers: int = int(os.getenv("WORKERS", "2"))

    # AWS
    aws_s3_bucket: str = os.getenv("AWS_S3_BUCKET", "")
    aws_kms_key_id: str = os.getenv("AWS_KMS_KEY_ID", "")

    # Azure
    azure_storage_account: str = os.getenv("AZURE_STORAGE_ACCOUNT", "")
    azure_container_name: str = os.getenv("AZURE_CONTAINER_NAME", "mission-telemetry")
    azure_key_vault_url: str = os.getenv("AZURE_KEY_VAULT_URL", "")

    # Cross-cloud
    vpn_remote_endpoint: str = os.getenv("VPN_REMOTE_ENDPOINT", "")
    replication_enabled: bool = os.getenv("REPLICATION_ENABLED", "true").lower() == "true"

    # Security
    encryption_algorithm: str = "AES-256-GCM"
    min_tls_version: str = "1.2"


config = Config()
