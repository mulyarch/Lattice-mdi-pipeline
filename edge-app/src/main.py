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
