"""Cortex — Unit tests for the Consumer Lambda handler."""

from __future__ import annotations

import json
import os
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch
from uuid import uuid4

os.environ["TABLE_NAME"] = "cortex-events"
os.environ["POWERTOOLS_SERVICE_NAME"] = "cortex-consumer-test"
os.environ["LOG_LEVEL"] = "DEBUG"


def _make_event_record(event_id=None, source="server-web-01", event_type="cpu_usage", severity="warning"):
    return {
        "event_id": event_id or str(uuid4()),
        "source": source,
        "event_type": event_type,
        "severity": severity,
        "data": {"cpu_percent": 87.5},
        "timestamp": datetime.now(UTC).isoformat(),
        "hostname": "ip-10-0-1-42",
        "region": "us-east-1",
        "tags": {"env": "prod"},
        "request_id": "req-123",
        "source_ip": "10.0.0.1",
        "ingested_at": datetime.now(UTC).isoformat(),
    }


def _make_sqs_event(records):
    return {
        "Records": [
            {
                "messageId": f"msg-{i:04d}",
                "receiptHandle": f"r-{i}",
                "body": json.dumps(r),
                "attributes": {},
                "messageAttributes": {},
            }
            for i, r in enumerate(records)
        ]
    }


class TestConsumerHappyPath:
    @patch("src.consumer.handler.dynamodb")
    def test_single_record_no_failures(self, mock_ddb):
        from src.consumer.handler import handler

        mock_ddb.Table.return_value = MagicMock()
        result = handler(_make_sqs_event([_make_event_record()]), MagicMock())
        assert result["batchItemFailures"] == []

    @patch("src.consumer.handler.dynamodb")
    def test_batch_all_succeed(self, mock_ddb):
        from src.consumer.handler import handler

        mock_ddb.Table.return_value = MagicMock()
        result = handler(_make_sqs_event([_make_event_record() for _ in range(5)]), MagicMock())
        assert result["batchItemFailures"] == []
        assert mock_ddb.Table.return_value.put_item.call_count == 5


class TestConsumerPartialFailure:
    @patch("src.consumer.handler.dynamodb")
    def test_one_failure_reports_only_failed_id(self, mock_ddb):
        from src.consumer.handler import handler

        t = MagicMock()
        mock_ddb.Table.return_value = t
        t.put_item.side_effect = [None, Exception("err"), None]
        result = handler(_make_sqs_event([_make_event_record() for _ in range(3)]), MagicMock())
        assert len(result["batchItemFailures"]) == 1
        assert result["batchItemFailures"][0]["itemIdentifier"] == "msg-0001"

    @patch("src.consumer.handler.dynamodb")
    def test_all_fail(self, mock_ddb):
        from src.consumer.handler import handler

        t = MagicMock()
        mock_ddb.Table.return_value = t
        t.put_item.side_effect = Exception("down")
        result = handler(_make_sqs_event([_make_event_record() for _ in range(3)]), MagicMock())
        assert len(result["batchItemFailures"]) == 3


class TestConsumerIdempotency:
    @patch("src.consumer.handler.dynamodb")
    def test_duplicate_silently_skipped(self, mock_ddb):
        from botocore.exceptions import ClientError

        from src.consumer.handler import handler

        t = MagicMock()
        mock_ddb.Table.return_value = t
        t.put_item.side_effect = ClientError(
            {"Error": {"Code": "ConditionalCheckFailedException", "Message": "dup"}}, "PutItem"
        )
        result = handler(_make_sqs_event([_make_event_record()]), MagicMock())
        assert result["batchItemFailures"] == []

    @patch("src.consumer.handler.dynamodb")
    def test_other_dynamodb_error_is_failure(self, mock_ddb):
        from botocore.exceptions import ClientError

        from src.consumer.handler import handler

        t = MagicMock()
        mock_ddb.Table.return_value = t
        t.put_item.side_effect = ClientError(
            {"Error": {"Code": "ProvisionedThroughputExceededException", "Message": "rate"}}, "PutItem"
        )
        result = handler(_make_sqs_event([_make_event_record()]), MagicMock())
        assert len(result["batchItemFailures"]) == 1


class TestConsumerMalformed:
    @patch("src.consumer.handler.dynamodb")
    def test_invalid_json_is_failure(self, mock_ddb):
        from src.consumer.handler import handler

        event = {"Records": [{"messageId": "bad", "body": "not json", "attributes": {}, "messageAttributes": {}}]}
        result = handler(event, MagicMock())
        assert len(result["batchItemFailures"]) == 1
