"""Cortex — Unit tests for the Producer Lambda handler."""

from __future__ import annotations

import json
import os
from unittest.mock import MagicMock, patch

# Set environment variables BEFORE importing the handler
os.environ["QUEUE_URL"] = "https://sqs.us-east-1.amazonaws.com/123456789012/cortex-events-queue"
os.environ["POWERTOOLS_SERVICE_NAME"] = "cortex-producer-test"
os.environ["LOG_LEVEL"] = "DEBUG"


def _make_apigw_event(body: dict | str | None = None, api_key: str | None = None) -> dict:
    """Build a minimal API Gateway v2 proxy event."""
    headers = {"content-type": "application/json"}
    if api_key:
        headers["x-api-key"] = api_key

    event = {
        "version": "2.0",
        "routeKey": "POST /events",
        "rawPath": "/events",
        "headers": headers,
        "requestContext": {
            "requestId": "test-request-id-12345",
            "http": {
                "method": "POST",
                "path": "/events",
                "sourceIp": "127.0.0.1",
            },
        },
        "body": json.dumps(body) if isinstance(body, dict) else body,
        "isBase64Encoded": False,
    }
    return event


def _valid_payload() -> dict:
    """Return a valid infrastructure monitoring payload."""
    return {
        "source": "server-web-01",
        "event_type": "cpu_usage",
        "severity": "warning",
        "data": {
            "cpu_percent": 87.5,
            "load_avg_1m": 2.3,
            "cores": 4,
        },
        "hostname": "ip-10-0-1-42",
        "region": "us-east-1",
        "tags": {"env": "production", "team": "platform"},
    }


# ──────────────────────────────────────────────
# Happy path tests
# ──────────────────────────────────────────────


class TestProducerHappyPath:
    """Tests for successful event ingestion."""

    @patch("producer.handler.sqs_client")
    def test_valid_event_returns_202(self, mock_sqs: MagicMock) -> None:
        """A valid payload should return 202 Accepted with message_id."""
        from producer.handler import handler

        mock_sqs.send_message.return_value = {"MessageId": "msg-abc-123"}
        event = _make_apigw_event(body=_valid_payload())
        context = MagicMock()

        result = handler(event, context)

        assert result["statusCode"] == 202
        body = json.loads(result["body"])
        assert body["status"] == "accepted"
        assert body["message_id"] == "msg-abc-123"
        assert "event_id" in body

    @patch("producer.handler.sqs_client")
    def test_sqs_send_message_called_with_correct_queue(self, mock_sqs: MagicMock) -> None:
        """The handler should send to the queue URL from environment."""
        from producer.handler import handler

        mock_sqs.send_message.return_value = {"MessageId": "msg-xyz"}
        event = _make_apigw_event(body=_valid_payload())
        context = MagicMock()

        handler(event, context)

        call_kwargs = mock_sqs.send_message.call_args
        assert call_kwargs.kwargs["QueueUrl"] == os.environ["QUEUE_URL"]

    @patch("producer.handler.sqs_client")
    def test_message_attributes_include_event_type(self, mock_sqs: MagicMock) -> None:
        """SQS message attributes should include event_type and severity."""
        from producer.handler import handler

        mock_sqs.send_message.return_value = {"MessageId": "msg-xyz"}
        event = _make_apigw_event(body=_valid_payload())
        context = MagicMock()

        handler(event, context)

        call_kwargs = mock_sqs.send_message.call_args.kwargs
        attrs = call_kwargs["MessageAttributes"]
        assert attrs["event_type"]["StringValue"] == "cpu_usage"
        assert attrs["severity"]["StringValue"] == "warning"
        assert attrs["source"]["StringValue"] == "server-web-01"

    @patch("producer.handler.sqs_client")
    def test_minimal_payload_accepted(self, mock_sqs: MagicMock) -> None:
        """A minimal payload with only required fields should be accepted."""
        from producer.handler import handler

        mock_sqs.send_message.return_value = {"MessageId": "msg-min"}
        payload = {
            "source": "sensor-01",
            "event_type": "health_check",
            "data": {},
        }
        event = _make_apigw_event(body=payload)
        context = MagicMock()

        result = handler(event, context)
        assert result["statusCode"] == 202

    @patch("producer.handler.sqs_client")
    def test_timestamp_auto_filled_when_missing(self, mock_sqs: MagicMock) -> None:
        """If timestamp is omitted, it should be auto-filled with UTC now."""
        from producer.handler import handler

        mock_sqs.send_message.return_value = {"MessageId": "msg-ts"}
        payload = _valid_payload()
        # No timestamp in payload
        assert "timestamp" not in payload or payload.get("timestamp") is None

        event = _make_apigw_event(body=payload)
        context = MagicMock()

        handler(event, context)

        # Check the body sent to SQS contains a timestamp
        call_kwargs = mock_sqs.send_message.call_args.kwargs
        body = json.loads(call_kwargs["MessageBody"])
        assert body["timestamp"] is not None


# ──────────────────────────────────────────────
# Validation error tests
# ──────────────────────────────────────────────


class TestProducerValidation:
    """Tests for payload validation errors."""

    def test_empty_body_returns_400(self) -> None:
        """An empty request body should return 400."""
        from producer.handler import handler

        event = _make_apigw_event(body=None)
        event["body"] = ""
        context = MagicMock()

        result = handler(event, context)
        assert result["statusCode"] == 400

    def test_invalid_json_returns_400(self) -> None:
        """Malformed JSON should return 400."""
        from producer.handler import handler

        event = _make_apigw_event()
        event["body"] = "this is not valid json {{"
        context = MagicMock()

        result = handler(event, context)
        assert result["statusCode"] == 400
        body = json.loads(result["body"])
        assert body["status"] == "error"

    def test_missing_source_returns_422(self) -> None:
        """Missing required field 'source' should return 422."""
        from producer.handler import handler

        payload = {"event_type": "cpu_usage", "data": {"cpu": 50}}
        event = _make_apigw_event(body=payload)
        context = MagicMock()

        result = handler(event, context)
        assert result["statusCode"] == 422

    def test_missing_data_returns_422(self) -> None:
        """Missing required field 'data' should return 422."""
        from producer.handler import handler

        payload = {"source": "test", "event_type": "cpu_usage"}
        event = _make_apigw_event(body=payload)
        context = MagicMock()

        result = handler(event, context)
        assert result["statusCode"] == 422

    def test_invalid_event_type_returns_422(self) -> None:
        """An invalid event_type enum value should return 422."""
        from producer.handler import handler

        payload = {
            "source": "test",
            "event_type": "this_is_not_a_valid_type",
            "data": {},
        }
        event = _make_apigw_event(body=payload)
        context = MagicMock()

        result = handler(event, context)
        assert result["statusCode"] == 422

    def test_source_too_long_returns_422(self) -> None:
        """A source string exceeding max_length should return 422."""
        from producer.handler import handler

        payload = {
            "source": "x" * 300,  # max_length is 256
            "event_type": "cpu_usage",
            "data": {},
        }
        event = _make_apigw_event(body=payload)
        context = MagicMock()

        result = handler(event, context)
        assert result["statusCode"] == 422


# ──────────────────────────────────────────────
# API Key validation tests
# ──────────────────────────────────────────────


class TestProducerAPIKey:
    """Tests for API key header validation."""

    @patch("producer.handler.sqs_client")
    def test_open_mode_no_key_configured(self, mock_sqs: MagicMock) -> None:
        """When CORTEX_API_KEY is not set, requests pass without auth."""
        from producer.handler import handler

        mock_sqs.send_message.return_value = {"MessageId": "msg-open"}

        # Ensure no API key is configured
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("CORTEX_API_KEY", None)
            event = _make_apigw_event(body=_valid_payload())
            context = MagicMock()

            result = handler(event, context)
            assert result["statusCode"] == 202

    @patch("producer.handler.sqs_client")
    def test_valid_api_key_accepted(self, mock_sqs: MagicMock) -> None:
        """A matching API key should be accepted."""
        from producer.handler import handler

        mock_sqs.send_message.return_value = {"MessageId": "msg-auth"}

        with patch.dict(os.environ, {"CORTEX_API_KEY": "my-secret-key"}):
            event = _make_apigw_event(body=_valid_payload(), api_key="my-secret-key")
            context = MagicMock()

            result = handler(event, context)
            assert result["statusCode"] == 202

    def test_missing_api_key_returns_401(self) -> None:
        """When a key is configured but not provided, return 401."""
        from producer.handler import handler

        with patch.dict(os.environ, {"CORTEX_API_KEY": "my-secret-key"}):
            event = _make_apigw_event(body=_valid_payload())  # No api_key header
            context = MagicMock()

            result = handler(event, context)
            assert result["statusCode"] == 401

    def test_wrong_api_key_returns_401(self) -> None:
        """An incorrect API key should return 401."""
        from producer.handler import handler

        with patch.dict(os.environ, {"CORTEX_API_KEY": "correct-key"}):
            event = _make_apigw_event(body=_valid_payload(), api_key="wrong-key")
            context = MagicMock()

            result = handler(event, context)
            assert result["statusCode"] == 401


# ──────────────────────────────────────────────
# SQS failure tests
# ──────────────────────────────────────────────


class TestProducerSQSFailure:
    """Tests for SQS send failures."""

    @patch("producer.handler.sqs_client")
    def test_sqs_error_returns_500(self, mock_sqs: MagicMock) -> None:
        """If SQS send_message fails, return 500."""
        from producer.handler import handler

        mock_sqs.send_message.side_effect = Exception("SQS connection timeout")
        event = _make_apigw_event(body=_valid_payload())
        context = MagicMock()

        result = handler(event, context)
        assert result["statusCode"] == 500
        body = json.loads(result["body"])
        assert body["status"] == "error"
