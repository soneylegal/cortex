"""Cortex Consumer Lambda — Processes SQS messages and persists to DynamoDB.

Flow:
    SQS Main Queue → this handler → DynamoDB

Responsibilities:
    1. Receive batch of SQS messages
    2. Parse and validate each message body (EventRecord)
    3. Write to DynamoDB with conditional expression for idempotency
    4. Report only failed items (ReportBatchItemFailures pattern)
    5. Messages that fail maxReceiveCount times go to DLQ automatically
"""

from __future__ import annotations

import json
from typing import Any

import boto3
from botocore.exceptions import ClientError

from shared.constants import DEFAULT_REGION, PK_FIELD, SK_FIELD, get_table_name
from shared.logger import LambdaContext, Tracer, get_logger
from shared.schemas import EventRecord

logger = get_logger(service="cortex-consumer")
tracer = Tracer(service="cortex-consumer")
dynamodb = boto3.resource("dynamodb", region_name=DEFAULT_REGION)


# ──────────────────────────────────────────────
# DynamoDB persistence
# ──────────────────────────────────────────────


def _persist_record(record: EventRecord, table_name: str) -> None:
    """Write an EventRecord to DynamoDB with idempotency guard.

    Uses a ConditionExpression to prevent overwriting an existing item
    with the same (event_id, timestamp) composite key.

    Raises:
        ClientError: If the write fails for reasons other than
            a duplicate key (ConditionalCheckFailedException is swallowed).
    """
    table = dynamodb.Table(table_name)
    item: dict[str, Any] = record.model_dump(exclude_none=True)

    try:
        table.put_item(
            Item=item,
            ConditionExpression=f"attribute_not_exists({PK_FIELD}) AND attribute_not_exists({SK_FIELD})",
        )
        logger.info(
            "Record persisted",
            extra={"event_id": record.event_id, "event_type": record.event_type},
        )
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            # Duplicate — idempotent, safe to ignore
            logger.info(
                "Duplicate record skipped",
                extra={"event_id": record.event_id},
            )
        else:
            raise


# ──────────────────────────────────────────────
# Message processing
# ──────────────────────────────────────────────


@tracer.capture_method
def _process_record(sqs_record: dict, table_name: str) -> None:
    """Parse an SQS record body and persist to DynamoDB.

    Args:
        sqs_record: A single record from ``event["Records"]``.
        table_name: DynamoDB table name.

    Raises:
        Exception: Any unhandled error during processing.
    """
    body = sqs_record["body"]
    payload = json.loads(body)
    event_record = EventRecord.model_validate(payload)

    logger.info(
        "Processing event",
        extra={
            "event_id": event_record.event_id,
            "source": event_record.source,
            "event_type": event_record.event_type,
            "severity": event_record.severity,
            "message_id": sqs_record.get("messageId"),
        },
    )

    _persist_record(event_record, table_name)


# ──────────────────────────────────────────────
# Handler
# ──────────────────────────────────────────────


@logger.inject_lambda_context(log_event=True)
@tracer.capture_lambda_handler
def handler(event: dict, context: LambdaContext) -> dict:
    """Lambda entrypoint — SQS batch trigger.

    Implements the ReportBatchItemFailures pattern:
    only failed message IDs are returned so that SQS reprocesses
    them individually instead of retrying the entire batch.
    """
    records = event.get("Records", [])
    table_name = get_table_name()
    batch_item_failures: list[dict[str, str]] = []

    logger.info("Batch received", extra={"batch_size": len(records)})

    for sqs_record in records:
        message_id = sqs_record.get("messageId", "unknown")
        try:
            _process_record(sqs_record, table_name)
        except Exception:
            logger.exception(
                "Failed to process record",
                extra={"message_id": message_id},
            )
            batch_item_failures.append({"itemIdentifier": message_id})

    if batch_item_failures:
        logger.warning(
            "Batch partially failed",
            extra={
                "total": len(records),
                "failed": len(batch_item_failures),
                "failed_ids": [f["itemIdentifier"] for f in batch_item_failures],
            },
        )
    else:
        logger.info("Batch fully processed", extra={"total": len(records)})

    return {"batchItemFailures": batch_item_failures}
