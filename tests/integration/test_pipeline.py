"""Cortex — Integration tests (requires LocalStack running)."""

from __future__ import annotations

import os

import boto3
import pytest

pytestmark = pytest.mark.integration

LOCALSTACK_URL = os.environ.get("LOCALSTACK_URL", "http://localhost:4566")
REGION = "us-east-1"
QUEUE_NAME = "cortex-events-queue"
DLQ_NAME = "cortex-events-dlq"
TABLE_NAME = "cortex-events"


@pytest.fixture(scope="module")
def aws_clients():
    """Create boto3 clients pointing at LocalStack."""
    kwargs = {
        "region_name": REGION,
        "endpoint_url": LOCALSTACK_URL,
        "aws_access_key_id": "test",
        "aws_secret_access_key": "test",
    }
    return {
        "sqs": boto3.client("sqs", **kwargs),
        "dynamodb": boto3.client("dynamodb", **kwargs),
        "lambda_": boto3.client("lambda", **kwargs),
    }


class TestPipelineE2E:
    """End-to-end tests against LocalStack (run after make deploy-local)."""

    def test_localstack_is_running(self, aws_clients):
        """Verify LocalStack is accessible."""
        import urllib.request

        resp = urllib.request.urlopen(f"{LOCALSTACK_URL}/_localstack/health")
        assert resp.status == 200

    def test_sqs_queues_exist(self, aws_clients):
        """Both main queue and DLQ should be provisioned."""
        sqs = aws_clients["sqs"]
        queues = sqs.list_queues(QueueNamePrefix="cortex-")
        urls = queues.get("QueueUrls", [])
        names = [u.split("/")[-1] for u in urls]
        assert QUEUE_NAME in names
        assert DLQ_NAME in names

    def test_dynamodb_table_exists(self, aws_clients):
        """The events table should be provisioned."""
        ddb = aws_clients["dynamodb"]
        tables = ddb.list_tables()["TableNames"]
        assert TABLE_NAME in tables

    def test_lambda_functions_exist(self, aws_clients):
        """Both producer and consumer Lambdas should be deployed."""
        lam = aws_clients["lambda_"]
        functions = lam.list_functions()["Functions"]
        names = [f["FunctionName"] for f in functions]
        assert "cortex-producer" in names
        assert "cortex-consumer" in names
