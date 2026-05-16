"""Cortex — Centralized structured logging with AWS Lambda Powertools."""

from __future__ import annotations

from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities.typing import LambdaContext


def get_logger(service: str | None = None, **kwargs: object) -> Logger:
    """Create a pre-configured Powertools Logger.

    Args:
        service: Service name override. Falls back to POWERTOOLS_SERVICE_NAME env var.
        **kwargs: Additional keyword arguments forwarded to ``Logger()``.

    Returns:
        A ``Logger`` instance with structured JSON output.
    """
    return Logger(
        service=service,
        log_uncaught_exceptions=True,
        **kwargs,
    )


def extract_correlation_id(event: dict) -> str | None:
    """Extract a correlation/request ID from an API Gateway v2 event.

    Falls back through several common locations in the event payload.
    """
    # HTTP API v2 format
    request_context = event.get("requestContext", {})
    return request_context.get("requestId")


def extract_source_ip(event: dict) -> str | None:
    """Extract the caller's source IP from an API Gateway v2 event."""
    request_context = event.get("requestContext", {})
    http_info = request_context.get("http", {})
    return http_info.get("sourceIp")


__all__ = [
    "LambdaContext",
    "Logger",
    "Tracer",
    "extract_correlation_id",
    "extract_source_ip",
    "get_logger",
]
