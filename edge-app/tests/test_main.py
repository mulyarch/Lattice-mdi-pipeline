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
