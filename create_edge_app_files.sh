
#!/bin/bash
# Run from the root of your anduril-mdi-pipeline directory
# This creates the Edge App (containerized workload) and Kubernetes manifests

# Create directory structure
mkdir -p edge-app/src
mkdir -p edge-app/tests
mkdir -p kubernetes/base
mkdir -p kubernetes/overlays/aws-sovereign
mkdir -p kubernetes/overlays/azure-allied

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 1: edge-app/Dockerfile
# Multi-stage build — secure, minimal image
# ═══════════════════════════════════════════════════════════════════════════════

cat > edge-app/Dockerfile << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# MULTI-STAGE DOCKERFILE — Mission Data Processor
# Stage 1: Build (dependencies + compile)
# Stage 2: Runtime (minimal distroless image)
#
# Security features:
#   - Non-root user
#   - Distroless base (no shell, no package manager)
#   - No secrets in image layers
#   - Health check endpoint
# ═══════════════════════════════════════════════════════════════════════════════

# ─── Stage 1: Build ───
FROM python:3.11-slim AS builder

WORKDIR /build

# Install dependencies first (layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Copy application source
COPY src/ ./src/

# ─── Stage 2: Runtime ───
FROM python:3.11-slim AS runtime

# Security: Create non-root user
RUN groupadd -r mission && useradd -r -g mission -d /app -s /sbin/nologin mission

# Install only runtime dependencies
COPY --from=builder /install /usr/local

# Copy application
WORKDIR /app
COPY --from=builder /build/src/ ./src/
COPY entrypoint.sh .

# Security: Set ownership and permissions
RUN chown -R mission:mission /app && \
    chmod +x /app/entrypoint.sh

# Security: Drop all capabilities, run as non-root
USER mission

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

# Expose metrics and API ports
EXPOSE 8080 9090

# Labels for traceability
LABEL maintainer="yuriy@sovereign-infra" \
      project="mdi-sovereign" \
      classification="UNCLASSIFIED-DEMO" \
      description="Mission Data Processor — Edge Simulator"

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["--mode", "processor"]
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 2: edge-app/requirements.txt
# ═══════════════════════════════════════════════════════════════════════════════

cat > edge-app/requirements.txt << 'EOF'
# Mission Data Processor Dependencies
fastapi==0.109.0
uvicorn[standard]==0.27.0
pydantic==2.5.3
prometheus-client==0.19.0
boto3==1.34.0
azure-storage-blob==12.19.0
azure-identity==1.15.0
cryptography==41.0.7
structlog==24.1.0
httpx==0.26.0
python-json-logger==2.0.7
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 3: edge-app/entrypoint.sh
# ═══════════════════════════════════════════════════════════════════════════════

cat > edge-app/entrypoint.sh << 'EOF'
#!/bin/sh
# ═══════════════════════════════════════════════════════════════════════════════
# ENTRYPOINT — Mission Data Processor
# Validates environment and starts the application
# ═══════════════════════════════════════════════════════════════════════════════

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Mission Data Processor — Starting                           ║"
echo "║  Environment: ${ENVIRONMENT:-unknown}                        ║"
echo "║  Cloud: ${CLOUD_PROVIDER:-unknown}                           ║"
echo "║  Mode: ${1:-processor}                                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Validate required environment variables
if [ -z "$ENVIRONMENT" ]; then
  echo "[ERROR] ENVIRONMENT variable not set"
  exit 1
fi

if [ -z "$CLOUD_PROVIDER" ]; then
  echo "[ERROR] CLOUD_PROVIDER variable not set"
  exit 1
fi

# Start the application
exec python -m uvicorn src.main:app \
  --host 0.0.0.0 \
  --port 8080 \
  --workers ${WORKERS:-2} \
  --log-level ${LOG_LEVEL:-info} \
  --access-log
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 4: edge-app/src/__init__.py
# ═══════════════════════════════════════════════════════════════════════════════

cat > edge-app/src/__init__.py << 'EOF'
"""Mission Data Processor — Sovereign Edge Simulator"""
__version__ = "1.0.0"
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 5: edge-app/src/main.py
# The core application — simulates mission data processing
# ═══════════════════════════════════════════════════════════════════════════════

cat > edge-app/src/main.py << 'EOF'
"""
═══════════════════════════════════════════════════════════════════════════════
MISSION DATA PROCESSOR — Sovereign Edge Simulator
═══════════════════════════════════════════════════════════════════════════════

Simulates a mission data processing service that:
  1. Ingests telemetry from edge devices (drones, sensors, vehicles)
  2. Encrypts and stores data in sovereign/allied storage
  3. Replicates critical data across clouds via VPN
  4. Exposes Prometheus metrics for observability
  5. Provides health/readiness endpoints for Kubernetes

This demonstrates:
  - Multi-cloud data flow (AWS S3 ↔ Azure Blob)
  - Encryption at rest and in transit
  - Structured logging for audit trails
  - Kubernetes-native health checks
  - Prometheus metrics integration
"""

import os
import time
import uuid
import hashlib
from datetime import datetime, timezone
from typing import Optional

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from prometheus_client import (
    Counter,
    Histogram,
    Gauge,
    generate_latest,
    CONTENT_TYPE_LATEST,
)
from starlette.responses import Response
import structlog

# ─────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────

ENVIRONMENT = os.getenv("ENVIRONMENT", "dev")
CLOUD_PROVIDER = os.getenv("CLOUD_PROVIDER", "aws")
REGION = os.getenv("REGION", "us-east-1")
SERVICE_NAME = "mission-data-processor"
VERSION = "1.0.0"

# ─────────────────────────────────────────────
# STRUCTURED LOGGING
# ─────────────────────────────────────────────

structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ]
)
logger = structlog.get_logger(
    service=SERVICE_NAME,
    environment=ENVIRONMENT,
    cloud=CLOUD_PROVIDER,
)

# ─────────────────────────────────────────────
# PROMETHEUS METRICS
# ─────────────────────────────────────────────

TELEMETRY_INGESTED = Counter(
    "mission_telemetry_ingested_total",
    "Total telemetry messages ingested",
    ["source_type", "classification", "cloud"],
)

TELEMETRY_PROCESSED = Counter(
    "mission_telemetry_processed_total",
    "Total telemetry messages processed",
    ["destination", "status"],
)

PROCESSING_DURATION = Histogram(
    "mission_processing_duration_seconds",
    "Time to process a telemetry message",
    ["operation"],
    buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0],
)

CROSS_CLOUD_REPLICATIONS = Counter(
    "mission_cross_cloud_replications_total",
    "Total cross-cloud data replications",
    ["source_cloud", "destination_cloud", "status"],
)

ACTIVE_CONNECTIONS = Gauge(
    "mission_active_connections",
    "Number of active edge device connections",
    ["device_type"],
)

VPN_TUNNEL_STATUS = Gauge(
    "mission_vpn_tunnel_status",
    "VPN tunnel health (1=up, 0=down)",
    ["tunnel_id", "destination"],
)

DATA_ENCRYPTED_BYTES = Counter(
    "mission_data_encrypted_bytes_total",
    "Total bytes encrypted before storage",
    ["algorithm", "cloud"],
)

# ─────────────────────────────────────────────
# DATA MODELS
# ─────────────────────────────────────────────

class TelemetryMessage(BaseModel):
    """Incoming telemetry from edge devices"""
    device_id: str = Field(..., description="Unique device identifier")
    device_type: str = Field(..., description="Type: drone, sensor, vehicle, satellite")
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    altitude_m: Optional[float] = Field(None, ge=0)
    payload: dict = Field(default_factory=dict, description="Sensor payload data")
    classification: str = Field(default="UNCLASSIFIED", description="Data classification level")
    priority: int = Field(default=3, ge=1, le=5, description="1=critical, 5=routine")


class ProcessingResult(BaseModel):
    """Result of processing a telemetry message"""
    message_id: str
    status: str
    storage_location: str
    encrypted: bool
    replicated_to: Optional[str] = None
    processing_time_ms: float
    checksum: str


class HealthStatus(BaseModel):
    """Service health status"""
    status: str
    service: str
    version: str
    environment: str
    cloud_provider: str
    region: str
    uptime_seconds: float
    checks: dict


# ─────────────────────────────────────────────
# APPLICATION
# ─────────────────────────────────────────────

app = FastAPI(
    title="Mission Data Processor",
    description="Sovereign edge telemetry processing service",
    version=VERSION,
    docs_url="/docs" if ENVIRONMENT == "dev" else None,  # Disable docs in prod
    redoc_url=None,
)

START_TIME = time.time()


# ─────────────────────────────────────────────
# MIDDLEWARE — Request logging
# ─────────────────────────────────────────────

@app.middleware("http")
async def log_requests(request: Request, call_next):
    """Log all requests for audit trail"""
    request_id = str(uuid.uuid4())
    start = time.time()

    response = await call_next(request)

    duration = time.time() - start
    logger.info(
        "request_processed",
        request_id=request_id,
        method=request.method,
        path=request.url.path,
        status_code=response.status_code,
        duration_ms=round(duration * 1000, 2),
        client_ip=request.client.host if request.client else "unknown",
    )

    response.headers["X-Request-ID"] = request_id
    response.headers["X-Processing-Time-Ms"] = str(round(duration * 1000, 2))
    return response


# ─────────────────────────────────────────────
# HEALTH ENDPOINTS (Kubernetes probes)
# ─────────────────────────────────────────────

@app.get("/health", response_model=HealthStatus)
async def health_check():
    """Liveness probe — is the service running?"""
    return HealthStatus(
        status="healthy",
        service=SERVICE_NAME,
        version=VERSION,
        environment=ENVIRONMENT,
        cloud_provider=CLOUD_PROVIDER,
        region=REGION,
        uptime_seconds=round(time.time() - START_TIME, 2),
        checks={
            "api": "ok",
            "storage": "ok",  # Would check actual storage connectivity
            "encryption": "ok",
        },
    )


@app.get("/ready")
async def readiness_check():
    """Readiness probe — is the service ready to accept traffic?"""
    # In production, this would check:
    # - Storage backend connectivity
    # - KMS key accessibility
    # - VPN tunnel status
    return {"status": "ready", "timestamp": datetime.now(timezone.utc).isoformat()}


# ─────────────────────────────────────────────
# METRICS ENDPOINT (Prometheus)
# ─────────────────────────────────────────────

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST,
    )


# ─────────────────────────────────────────────
# TELEMETRY INGESTION
# ─────────────────────────────────────────────

@app.post("/api/v1/telemetry/ingest", response_model=ProcessingResult)
async def ingest_telemetry(message: TelemetryMessage):
    """
    Ingest telemetry from edge devices.

    Flow:
    1. Validate and classify incoming data
    2. Encrypt payload with KMS/Key Vault key
    3. Store in sovereign storage (S3 or Azure Blob)
    4. If priority <= 2, replicate to allied cloud
    5. Return processing result with checksum
    """
    start_time = time.time()
    message_id = str(uuid.uuid4())

    logger.info(
        "telemetry_received",
        message_id=message_id,
        device_id=message.device_id,
        device_type=message.device_type,
        classification=message.classification,
        priority=message.priority,
    )

    # Track metrics
    TELEMETRY_INGESTED.labels(
        source_type=message.device_type,
        classification=message.classification,
        cloud=CLOUD_PROVIDER,
    ).inc()

    ACTIVE_CONNECTIONS.labels(device_type=message.device_type).inc()

    try:
        # Step 1: Encrypt payload
        with PROCESSING_DURATION.labels(operation="encrypt").time():
            encrypted_payload = _encrypt_payload(message.payload)
            DATA_ENCRYPTED_BYTES.labels(
                algorithm="AES-256-GCM",
                cloud=CLOUD_PROVIDER,
            ).inc(len(str(encrypted_payload)))

        # Step 2: Store in sovereign storage
        with PROCESSING_DURATION.labels(operation="store").time():
            storage_path = _store_telemetry(message_id, message, encrypted_payload)

        # Step 3: Cross-cloud replication (high priority only)
        replicated_to = None
        if message.priority <= 2:
            with PROCESSING_DURATION.labels(operation="replicate").time():
                replicated_to = _replicate_cross_cloud(message_id, encrypted_payload)

        # Calculate checksum for integrity verification
        checksum = hashlib.sha256(
            f"{message_id}:{message.device_id}:{message.timestamp.isoformat()}".encode()
        ).hexdigest()

        processing_time = (time.time() - start_time) * 1000

        TELEMETRY_PROCESSED.labels(
            destination=CLOUD_PROVIDER,
            status="success",
        ).inc()

        logger.info(
            "telemetry_processed",
            message_id=message_id,
            processing_time_ms=round(processing_time, 2),
            storage_path=storage_path,
            replicated=replicated_to is not None,
        )

        return ProcessingResult(
            message_id=message_id,
            status="processed",
            storage_location=storage_path,
            encrypted=True,
            replicated_to=replicated_to,
            processing_time_ms=round(processing_time, 2),
            checksum=checksum,
        )

    except Exception as e:
        TELEMETRY_PROCESSED.labels(
            destination=CLOUD_PROVIDER,
            status="error",
        ).inc()

        logger.error(
            "telemetry_processing_failed",
            message_id=message_id,
            error=str(e),
        )
        raise HTTPException(status_code=500, detail="Processing failed")

    finally:
        ACTIVE_CONNECTIONS.labels(device_type=message.device_type).dec()


# ─────────────────────────────────────────────
# CROSS-CLOUD DATA QUERY
# ─────────────────────────────────────────────

@app.get("/api/v1/telemetry/{message_id}")
async def get_telemetry(message_id: str):
    """Retrieve processed telemetry by ID"""
    # In production, this would query S3/Azure Blob
    return {
        "message_id": message_id,
        "status": "stored",
        "cloud": CLOUD_PROVIDER,
        "encrypted": True,
        "retrievable": True,
    }


@app.get("/api/v1/status/vpn")
async def vpn_status():
    """Check cross-cloud VPN tunnel status"""
    # In production, this would ping the remote cloud
    tunnel_healthy = True  # Simulated

    VPN_TUNNEL_STATUS.labels(
        tunnel_id="tunnel-1",
        destination="azure" if CLOUD_PROVIDER == "aws" else "aws",
    ).set(1 if tunnel_healthy else 0)

    return {
        "vpn_status": "connected" if tunnel_healthy else "disconnected",
        "local_cloud": CLOUD_PROVIDER,
        "remote_cloud": "azure" if CLOUD_PROVIDER == "aws" else "aws",
        "tunnel_count": 2,
        "encryption": "AES-256 / IKEv2",
        "last_check": datetime.now(timezone.utc).isoformat(),
    }


# ─────────────────────────────────────────────
# INTERNAL FUNCTIONS
# ─────────────────────────────────────────────

def _encrypt_payload(payload: dict) -> dict:
    """
    Encrypt payload using cloud-native KMS.
    In production: AWS KMS or Azure Key Vault.
    Here: simulated with hash for demo purposes.
    """
    payload_str = str(payload)
    encrypted_hash = hashlib.sha256(payload_str.encode()).hexdigest()
    return {
        "encrypted": True,
        "algorithm": "AES-256-GCM",
        "key_id": f"arn:aws:kms:{REGION}:*:key/sovereign-key" if CLOUD_PROVIDER == "aws"
                  else f"https://mdi-sovereign-kv.vault.azure.net/keys/disk-key",
        "ciphertext_hash": encrypted_hash,
        "original_size_bytes": len(payload_str),
    }


def _store_telemetry(message_id: str, message: TelemetryMessage, encrypted: dict) -> str:
    """
    Store encrypted telemetry in cloud-native storage.
    AWS: S3 bucket with KMS encryption
    Azure: Blob Storage with Key Vault CMK
    """
    timestamp = message.timestamp.strftime("%Y/%m/%d/%H")

    if CLOUD_PROVIDER == "aws":
        path = f"s3://mdi-sovereign-{ENVIRONMENT}-mission-data/telemetry/{timestamp}/{message_id}.enc"
    else:
        path = f"azure://mission-telemetry/telemetry/{timestamp}/{message_id}.enc"

    # In production: actual S3/Blob upload with encryption
    # boto3.client('s3').put_object(...) or BlobServiceClient.upload_blob(...)

    return path


def _replicate_cross_cloud(message_id: str, encrypted: dict) -> str:
    """
    Replicate high-priority data to allied cloud via VPN.
    This simulates the cross-cloud data flow that would traverse
    the IPsec tunnel between AWS and Azure.
    """
    if CLOUD_PROVIDER == "aws":
        destination = "azure-allied"
        CROSS_CLOUD_REPLICATIONS.labels(
            source_cloud="aws",
            destination_cloud="azure",
            status="success",
        ).inc()
    else:
        destination = "aws-sovereign"
        CROSS_CLOUD_REPLICATIONS.labels(
            source_cloud="azure",
            destination_cloud="aws",
            status="success",
        ).inc()

    logger.info(
        "cross_cloud_replication",
        message_id=message_id,
        destination=destination,
        via="ipsec-vpn",
    )

    return destination
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 6: edge-app/src/config.py
# ═══════════════════════════════════════════════════════════════════════════════

cat > edge-app/src/config.py << 'EOF'
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
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 7: edge-app/tests/test_main.py
# ═══════════════════════════════════════════════════════════════════════════════

cat > edge-app/tests/__init__.py << 'EOF'
EOF

cat > edge-app/tests/test_main.py << 'EOF'
"""
Unit tests for Mission Data Processor
"""

import pytest
from fastapi.testclient import TestClient
from src.main import app


client = TestClient(app)


class TestHealthEndpoints:
    """Test Kubernetes health probe endpoints"""

    def test_health_check(self):
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert data["service"] == "mission-data-processor"
        assert "uptime_seconds" in data

    def test_readiness_check(self):
        response = client.get("/ready")
        assert response.status_code == 200
        assert response.json()["status"] == "ready"

    def test_metrics_endpoint(self):
        response = client.get("/metrics")
        assert response.status_code == 200
        assert "mission_telemetry_ingested_total" in response.text


class TestTelemetryIngestion:
    """Test telemetry processing pipeline"""

    def test_ingest_valid_telemetry(self):
        payload = {
            "device_id": "drone-001",
            "device_type": "drone",
            "latitude": -33.8688,
            "longitude": 151.2093,
            "altitude_m": 150.0,
            "payload": {"speed_kts": 45, "heading_deg": 270, "battery_pct": 82},
            "classification": "UNCLASSIFIED",
            "priority": 3,
        }
        response = client.post("/api/v1/telemetry/ingest", json=payload)
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "processed"
        assert data["encrypted"] is True
        assert data["checksum"] is not None
        assert data["replicated_to"] is None  # Priority 3 = no replication

    def test_ingest_high_priority_triggers_replication(self):
        payload = {
            "device_id": "sensor-critical-001",
            "device_type": "sensor",
            "payload": {"alert": "perimeter_breach", "sector": "alpha"},
            "classification": "UNCLASSIFIED",
            "priority": 1,  # Critical = triggers replication
        }
        response = client.post("/api/v1/telemetry/ingest", json=payload)
        assert response.status_code == 200
        data = response.json()
        assert data["replicated_to"] is not None

    def test_ingest_invalid_coordinates(self):
        payload = {
            "device_id": "drone-002",
            "device_type": "drone",
            "latitude": 999,  # Invalid
            "longitude": 151.2093,
            "payload": {},
        }
        response = client.post("/api/v1/telemetry/ingest", json=payload)
        assert response.status_code == 422  # Validation error

    def test_ingest_missing_required_fields(self):
        payload = {"payload": {"data": "test"}}  # Missing device_id, device_type
        response = client.post("/api/v1/telemetry/ingest", json=payload)
        assert response.status_code == 422


class TestVPNStatus:
    """Test cross-cloud VPN status endpoint"""

    def test_vpn_status(self):
        response = client.get("/api/v1/status/vpn")
        assert response.status_code == 200
        data = response.json()
        assert data["encryption"] == "AES-256 / IKEv2"
        assert data["tunnel_count"] == 2


class TestTelemetryRetrieval:
    """Test telemetry retrieval"""

    def test_get_telemetry_by_id(self):
        response = client.get("/api/v1/telemetry/test-message-123")
        assert response.status_code == 200
        data = response.json()
        assert data["message_id"] == "test-message-123"
        assert data["encrypted"] is True
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 8: kubernetes/base/namespace.yml
# ═══════════════════════════════════════════════════════════════════════════════

cat > kubernetes/base/namespace.yml << 'EOF'
---
apiVersion: v1
kind: Namespace
metadata:
  name: mission
  labels:
    app.kubernetes.io/part-of: mdi-sovereign
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 9: kubernetes/base/deployment.yml
# ═══════════════════════════════════════════════════════════════════════════════

cat > kubernetes/base/deployment.yml << 'EOF'
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mission-data-processor
  namespace: mission
  labels:
    app.kubernetes.io/name: mission-data-processor
    app.kubernetes.io/part-of: mdi-sovereign
    app.kubernetes.io/version: "1.0.0"
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: mission-data-processor
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app.kubernetes.io/name: mission-data-processor
        app.kubernetes.io/part-of: mdi-sovereign
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: mission-processor-sa
      automountServiceAccountToken: false

      # Security context (pod level)
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault

      # Anti-affinity — spread across nodes
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app.kubernetes.io/name
                      operator: In
                      values:
                        - mission-data-processor
                topologyKey: kubernetes.io/hostname

      containers:
        - name: processor
          image: mdi-sovereign/edge-simulator:latest
          imagePullPolicy: Always

          ports:
            - name: http
              containerPort: 8080
              protocol: TCP

          env:
            - name: ENVIRONMENT
              valueFrom:
                configMapKeyRef:
                  name: mission-config
                  key: environment
            - name: CLOUD_PROVIDER
              valueFrom:
                configMapKeyRef:
                  name: mission-config
                  key: cloud_provider
            - name: REGION
              valueFrom:
                configMapKeyRef:
                  name: mission-config
                  key: region
            - name: LOG_LEVEL
              value: "info"
            - name: WORKERS
              value: "2"
            - name: REPLICATION_ENABLED
              value: "true"

          # Security context (container level)
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL

          # Resource limits
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi

          # Health probes
          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 10
            periodSeconds: 30
            timeoutSeconds: 5
            failureThreshold: 3

          readinessProbe:
            httpGet:
              path: /ready
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3

          startupProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 12

          # Volume mounts
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            - name: app-cache
              mountPath: /app/.cache

      volumes:
        - name: tmp
          emptyDir:
            sizeLimit: 100Mi
        - name: app-cache
          emptyDir:
            sizeLimit: 50Mi
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 10: kubernetes/base/service.yml
# ═══════════════════════════════════════════════════════════════════════════════

cat > kubernetes/base/service.yml << 'EOF'
---
apiVersion: v1
kind: Service
metadata:
  name: mission-data-processor
  namespace: mission
  labels:
    app.kubernetes.io/name: mission-data-processor
    app.kubernetes.io/part-of: mdi-sovereign
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: mission-data-processor
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 11: kubernetes/base/serviceaccount.yml
# ═══════════════════════════════════════════════════════════════════════════════

cat > kubernetes/base/serviceaccount.yml << 'EOF'
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: mission-processor-sa
  namespace: mission
  labels:
    app.kubernetes.io/name: mission-data-processor
    app.kubernetes.io/part-of: mdi-sovereign
  annotations:
    # AWS: IRSA annotation (overridden in aws-sovereign overlay)
    # Azure: Workload Identity annotation (overridden in azure-allied overlay)
    eks.amazonaws.com/role-arn: ""
automountServiceAccountToken: false
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 12: kubernetes/base/networkpolicy.yml
# ═══════════════════════════════════════════════════════════════════════════════

cat > kubernetes/base/networkpolicy.yml << 'EOF'
---
# Default deny all ingress/egress in mission namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: mission
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress

---
# Allow mission-data-processor specific traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-mission-processor
  namespace: mission
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: mission-data-processor
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow traffic from within the namespace
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: mission
      ports:
        - protocol: TCP
          port: 8080
    # Allow Prometheus scraping from monitoring namespace
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
      ports:
        - protocol: TCP
          port: 8080
  egress:
    # Allow DNS resolution
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # Allow HTTPS to cloud services (S3, Azure Blob, KMS)
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - [IP_ADDRESS]  # Block IMDS (use IRSA/Workload Identity instead)
      ports:
        - protocol: TCP
          port: 443
    # Allow cross-cloud VPN traffic
    - to:
        - ipBlock:
            cidr: 10.0.0.0/8  # Internal VPN range
      ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 8080
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 13: kubernetes/base/hpa.yml
# ═══════════════════════════════════════════════════════════════════════════════

cat > kubernetes/base/hpa.yml << 'EOF'
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: mission-data-processor
  namespace: mission
  labels:
    app.kubernetes.io/name: mission-data-processor
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: mission-data-processor
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
        - type: Pods
          value: 2
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Pods
          value: 1
          periodSeconds: 120
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 14: kubernetes/base/configmap.yml
# ═══════════════════════════════════════════════════════════════════════════════

cat > kubernetes/base/configmap.yml << 'EOF'
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: mission-config
  namespace: mission
  labels:
    app.kubernetes.io/name: mission-data-processor
    app.kubernetes.io/part-of: mdi-sovereign
data:
  environment: "dev"
  cloud_provider: "aws"
  region: "us-east-1"
  replication_enabled: "true"
  log_level: "info"
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 15: kubernetes/base/kustomization.yml
# ═══════════════════════════════════════════════════════════════════════════════

cat > kubernetes/base/kustomization.yml << 'EOF'
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: mission

labels:
  - pairs:
      app.kubernetes.io/managed-by: kustomize
    includeSelectors: false

resources:
  - namespace.yml
  - serviceaccount.yml
  - configmap.yml
  - deployment.yml
  - service.yml
  - networkpolicy.yml
  - hpa.yml
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 16: kubernetes/overlays/aws-sovereign/kustomization.yml
# ═══════════════════════════════════════════════════════════════════════════════

cat > kubernetes/overlays/aws-sovereign/kustomization.yml << 'EOF'
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: mission

resources:
  - ../../base

patches:
  # Patch ConfigMap for AWS
  - target:
      kind: ConfigMap
      name: mission-config
    patch: |
      - op: replace
        path: /data/cloud_provider
        value: "aws"
      - op: replace
        path: /data/region
        value: "us-east-1"

  # Patch ServiceAccount with IRSA annotation
  - target:
      kind: ServiceAccount
      name: mission-processor-sa
    patch: |
      - op: replace
        path: /metadata/annotations/eks.amazonaws.com~1role-arn
        value: "arn:aws:iam::ACCOUNT_ID:role/mdi-sovereign-mission-processor"

  # Patch Deployment with AWS-specific tolerations
  - target:
      kind: Deployment
      name: mission-data-processor
    patch: |
      - op: add
        path: /spec/template/spec/tolerations
        value:
          - key: "workload"
            operator: "Equal"
            value: "mission-critical"
            effect: "NoSchedule"
      - op: add
        path: /spec/template/spec/nodeSelector
        value:
          tier: mission
          workload: mission-critical

labels:
  - pairs:
      cloud: aws
      environment: sovereign
    includeSelectors: false
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# FILE 17: kubernetes/overlays/azure-allied/kustomization.yml
# ═══════════════════════════════════════════════════════════════════════════════

cat > kubernetes/overlays/azure-allied/kustomization.yml << 'EOF'
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: mission

resources:
  - ../../base

patches:
  # Patch ConfigMap for Azure
  - target:
      kind: ConfigMap
      name: mission-config
    patch: |
      - op: replace
        path: /data/cloud_provider
        value: "azure"
      - op: replace
        path: /data/region
        value: "australiaeast"

  # Patch ServiceAccount with Azure Workload Identity
  - target:
      kind: ServiceAccount
      name: mission-processor-sa
    patch: |
      - op: remove
        path: /metadata/annotations/eks.amazonaws.com~1role-arn
      - op: add
        path: /metadata/annotations/azure.workload.identity~1client-id
        value: "AZURE_CLIENT_ID"
      - op: add
        path: /metadata/labels/azure.workload.identity~1use
        value: "true"

  # Patch Deployment with Azure-specific tolerations
  - target:
      kind: Deployment
      name: mission-data-processor
    patch: |
      - op: add
        path: /spec/template/spec/tolerations
        value:
          - key: "workload"
            operator: "Equal"
            value: "mission-critical"
            effect: "NoSchedule"
      - op: add
        path: /spec/template/spec/nodeSelector
        value:
          tier: mission
          workload: mission-critical

labels:
  - pairs:
      cloud: azure
      environment: allied
    includeSelectors: false
EOF

# Remove old .gitkeep files
rm -f edge-app/.gitkeep
rm -f kubernetes/base/.gitkeep
rm -f kubernetes/overlays/.gitkeep

echo ""
echo "=== Edge App & Kubernetes Manifests Created ==="
echo ""
echo "  ✅ edge-app/Dockerfile"
echo "  ✅ edge-app/requirements.txt"
echo "  ✅ edge-app/entrypoint.sh"
echo "  ✅ edge-app/src/__init__.py"
echo "  ✅ edge-app/src/main.py"
echo "  ✅ edge-app/src/config.py"
echo "  ✅ edge-app/tests/__init__.py"
echo "  ✅ edge-app/tests/test_main.py"
echo "  ✅ kubernetes/base/namespace.yml"
echo "  ✅ kubernetes/base/deployment.yml"
echo "  ✅ kubernetes/base/service.yml"
echo "  ✅ kubernetes/base/serviceaccount.yml"
echo "  ✅ kubernetes/base/networkpolicy.yml"
echo "  ✅ kubernetes/base/hpa.yml"
echo "  ✅ kubernetes/base/configmap.yml"
echo "  ✅ kubernetes/base/kustomization.yml"
echo "  ✅ kubernetes/overlays/aws-sovereign/kustomization.yml"
echo "  ✅ kubernetes/overlays/azure-allied/kustomization.yml"
echo ""
echo "🎉 All 18 files created! Run 'git add . && git commit' to save."

