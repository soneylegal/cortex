"""Cortex — Shared constants for Lambda functions and Terraform references."""

import os

# ──────────────────────────────────────────────
# Environment variable keys (set by Terraform)
# ──────────────────────────────────────────────
ENV_QUEUE_URL = "QUEUE_URL"
ENV_TABLE_NAME = "TABLE_NAME"
ENV_LOG_LEVEL = "LOG_LEVEL"
ENV_API_KEY = "CORTEX_API_KEY"

# ──────────────────────────────────────────────
# AWS Resource defaults (used by scripts/tests)
# ──────────────────────────────────────────────
__version__ = "0.1.0"
PROJECT_NAME = "cortex"
DEFAULT_REGION = "us-east-1"
ENV_AWS_REGION = "AWS_DEFAULT_REGION"

QUEUE_NAME = f"{PROJECT_NAME}-events-queue"
DLQ_NAME = f"{PROJECT_NAME}-events-dlq"
TABLE_NAME = f"{PROJECT_NAME}-events"

# ──────────────────────────────────────────────
# DynamoDB schema
# ──────────────────────────────────────────────
PK_FIELD = "event_id"
SK_FIELD = "timestamp"
TTL_FIELD = "ttl"

# ──────────────────────────────────────────────
# API Key header name
# ──────────────────────────────────────────────
API_KEY_HEADER = "x-api-key"

# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────


def get_queue_url() -> str:
    """Return the SQS queue URL from the environment."""
    return os.environ[ENV_QUEUE_URL]


def get_table_name() -> str:
    """Return the DynamoDB table name from the environment."""
    return os.environ[ENV_TABLE_NAME]


def get_api_key() -> str | None:
    """Return the configured API key, or None if not set (open mode).

    An empty string is treated as 'not set' (open mode).
    """
    key = os.environ.get(ENV_API_KEY)
    return key if key else None
