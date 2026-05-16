"""Cortex Producer Lambda — Receives events from API Gateway, validates, and sends to SQS.

Flow:
    API Gateway (HTTP API v2) → this handler → SQS Main Queue

Responsibilities:
    1. Optional API Key validation (header x-api-key)
    2. Payload validation via Pydantic (IngestEvent schema)
    3. Enrichment with pipeline metadata (request_id, source_ip, timestamp)
    4. Send serialized EventRecord to SQS
    5. Return HTTP 202 Accepted with message_id
"""

from __future__ import annotations

import json
from http import HTTPStatus

import boto3
from pydantic import ValidationError

from shared.constants import API_KEY_HEADER, DEFAULT_REGION, get_api_key, get_queue_url
from shared.logger import LambdaContext, extract_correlation_id, extract_source_ip, get_logger
from shared.schemas import AcceptedResponse, ErrorResponse, EventRecord, IngestEvent

logger = get_logger(service="cortex-producer")
sqs_client = boto3.client("sqs", region_name=DEFAULT_REGION)


# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────


def _build_response(status_code: int, body: dict) -> dict:
    """Build an API Gateway v2 proxy response."""
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def _validate_api_key(event: dict) -> str | None:
    """Check the x-api-key header against the configured key.

    Returns:
        None if validation passes (or no key is configured).
        An error message string if validation fails.
    """
    expected_key = get_api_key()
    if expected_key is None:
        # Open mode — no authentication required
        return None

    headers = event.get("headers", {})
    # API Gateway v2 lowercases all header names
    provided_key = headers.get(API_KEY_HEADER) or headers.get(API_KEY_HEADER.upper())

    if not provided_key:
        return f"Missing required header: {API_KEY_HEADER}"
    if provided_key != expected_key:
        return "Invalid API key"

    return None


# ──────────────────────────────────────────────
# Handler
# ──────────────────────────────────────────────


@logger.inject_lambda_context(log_event=True)
def handler(event: dict, context: LambdaContext) -> dict:
    """Lambda entrypoint — API Gateway v2 proxy integration."""

    # 1. API Key validation
    auth_error = _validate_api_key(event)
    if auth_error:
        logger.warning("Authentication failed", extra={"reason": auth_error})
        error = ErrorResponse(message=auth_error)
        return _build_response(HTTPStatus.UNAUTHORIZED, error.model_dump())

    # 2. Parse and validate body
    raw_body = event.get("body", "")
    if event.get("isBase64Encoded", False):
        import base64

        raw_body = base64.b64decode(raw_body).decode("utf-8")

    if not raw_body:
        error = ErrorResponse(message="Request body is required")
        return _build_response(HTTPStatus.BAD_REQUEST, error.model_dump())

    try:
        payload = json.loads(raw_body)
    except json.JSONDecodeError as e:
        logger.warning("Invalid JSON body", extra={"error": str(e)})
        error = ErrorResponse(message="Invalid JSON body", details=[str(e)])
        return _build_response(HTTPStatus.BAD_REQUEST, error.model_dump())

    try:
        ingest_event = IngestEvent.model_validate(payload)
    except ValidationError as e:
        logger.warning("Validation failed", extra={"errors": e.error_count()})
        error = ErrorResponse(
            message="Payload validation failed",
            details=[err["msg"] for err in e.errors()],
        )
        return _build_response(HTTPStatus.UNPROCESSABLE_ENTITY, error.model_dump())

    # 3. Enrich with pipeline metadata
    request_id = extract_correlation_id(event)
    source_ip = extract_source_ip(event)

    record = EventRecord.from_ingest_event(
        ingest_event,
        request_id=request_id,
        source_ip=source_ip,
    )

    logger.info(
        "Event validated",
        extra={
            "event_id": record.event_id,
            "source": record.source,
            "event_type": record.event_type,
            "severity": record.severity,
        },
    )

    # 4. Send to SQS
    try:
        queue_url = get_queue_url()
        sqs_response = sqs_client.send_message(
            QueueUrl=queue_url,
            MessageBody=record.model_dump_json(),
            MessageAttributes={
                "event_type": {
                    "DataType": "String",
                    "StringValue": record.event_type,
                },
                "severity": {
                    "DataType": "String",
                    "StringValue": record.severity,
                },
                "source": {
                    "DataType": "String",
                    "StringValue": record.source,
                },
            },
        )
        message_id = sqs_response["MessageId"]
    except Exception:
        logger.exception("Failed to send message to SQS")
        error = ErrorResponse(message="Internal server error — failed to enqueue event")
        return _build_response(HTTPStatus.INTERNAL_SERVER_ERROR, error.model_dump())

    # 5. Return 202 Accepted
    logger.info("Event enqueued", extra={"message_id": message_id, "event_id": record.event_id})

    response = AcceptedResponse(
        message_id=message_id,
        event_id=record.event_id,
    )
    return _build_response(HTTPStatus.ACCEPTED, response.model_dump())
