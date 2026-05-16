"""Cortex — Pydantic schemas for Infrastructure Monitoring events."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from enum import StrEnum
from typing import Any

from pydantic import BaseModel, Field, field_validator

# ──────────────────────────────────────────────
# Enums
# ──────────────────────────────────────────────


class EventType(StrEnum):
    """Supported infrastructure monitoring event types."""

    CPU_USAGE = "cpu_usage"
    MEMORY_USAGE = "memory_usage"
    DISK_IO = "disk_io"
    NETWORK_LATENCY = "network_latency"
    NETWORK_THROUGHPUT = "network_throughput"
    PROCESS_COUNT = "process_count"
    UPTIME = "uptime"
    HEALTH_CHECK = "health_check"
    CUSTOM = "custom"


class Severity(StrEnum):
    """Severity levels for monitoring events."""

    INFO = "info"
    WARNING = "warning"
    CRITICAL = "critical"


# ──────────────────────────────────────────────
# Input Models
# ──────────────────────────────────────────────


class IngestEvent(BaseModel):
    """Payload sent by infrastructure agents to the Cortex pipeline.

    Example:
        {
            "source": "server-web-01",
            "event_type": "cpu_usage",
            "severity": "warning",
            "data": {"cpu_percent": 87.5, "load_avg_1m": 2.3, "cores": 4},
            "hostname": "ip-10-0-1-42",
            "region": "us-east-1",
            "tags": {"env": "production", "team": "platform"}
        }
    """

    source: str = Field(
        ...,
        min_length=1,
        max_length=256,
        description="Identifier of the reporting agent or service (e.g. 'server-web-01')",
    )
    event_type: EventType = Field(
        ...,
        description="Category of the monitoring event",
    )
    severity: Severity = Field(
        default=Severity.INFO,
        description="Severity level of the event",
    )
    data: dict[str, Any] = Field(
        ...,
        description="Metric payload — structure varies by event_type",
    )
    timestamp: datetime | None = Field(
        default=None,
        description="ISO-8601 timestamp; auto-filled with UTC now if omitted",
    )
    hostname: str | None = Field(
        default=None,
        max_length=256,
        description="Hostname of the reporting machine",
    )
    region: str | None = Field(
        default=None,
        max_length=64,
        description="Cloud region or datacenter (e.g. 'us-east-1')",
    )
    tags: dict[str, str] | None = Field(
        default=None,
        description="Arbitrary key-value labels for filtering",
    )

    @field_validator("timestamp", mode="before")
    @classmethod
    def _set_default_timestamp(cls, v: datetime | None) -> datetime:
        return v or datetime.now(UTC)


# ──────────────────────────────────────────────
# Enriched Record (stored in DynamoDB)
# ──────────────────────────────────────────────


class EventRecord(BaseModel):
    """Full record written to DynamoDB, enriched with pipeline metadata."""

    event_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    source: str
    event_type: str
    severity: str
    data: dict[str, Any]
    timestamp: str  # ISO-8601 string for DynamoDB sort key
    hostname: str | None = None
    region: str | None = None
    tags: dict[str, str] | None = None

    # Pipeline metadata
    request_id: str | None = None
    source_ip: str | None = None
    ingested_at: str = Field(
        default_factory=lambda: datetime.now(UTC).isoformat(),
    )

    @classmethod
    def from_ingest_event(
        cls,
        event: IngestEvent,
        *,
        request_id: str | None = None,
        source_ip: str | None = None,
    ) -> EventRecord:
        """Create an EventRecord from a validated IngestEvent."""
        return cls(
            source=event.source,
            event_type=event.event_type.value,
            severity=event.severity.value,
            data=event.data,
            timestamp=event.timestamp.isoformat() if event.timestamp else datetime.now(UTC).isoformat(),
            hostname=event.hostname,
            region=event.region,
            tags=event.tags,
            request_id=request_id,
            source_ip=source_ip,
        )


# ──────────────────────────────────────────────
# API Response Models
# ──────────────────────────────────────────────


class AcceptedResponse(BaseModel):
    """Response returned on successful event ingestion (HTTP 202)."""

    status: str = "accepted"
    message_id: str
    event_id: str


class ErrorResponse(BaseModel):
    """Response returned on validation or processing errors."""

    status: str = "error"
    message: str
    details: list[str] | None = None
