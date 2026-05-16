# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-05-16

### Added

- **Producer Lambda** — API Gateway → SQS ingestion with Pydantic schema validation
  - Optional `x-api-key` header authentication (open mode by default)
  - Payload enrichment with `request_id`, `source_ip`, and auto-generated `event_id`
  - Structured JSON logging via AWS Lambda Powertools
- **Consumer Lambda** — SQS → DynamoDB persistence with resilience patterns
  - `ReportBatchItemFailures` for partial batch failure handling
  - Idempotent writes via `ConditionExpression` (prevents duplicate events)
  - Graceful handling of malformed messages
- **Infrastructure as Code** (Terraform)
  - 9 `.tf` files covering Lambda, SQS, DynamoDB, API Gateway (REST v1), IAM, and CloudWatch
  - LocalStack toggle via `-var="use_localstack=true"`
  - Modular design with configurable variables (14 parameters)
- **SQS Dead Letter Queue** — automatic redrive after 3 failed processing attempts
- **DynamoDB table** — on-demand billing, composite key (`event_id` + `timestamp`), TTL support
- **API Gateway REST API** (v1) — `POST /events` endpoint with Lambda proxy integration
- **Shared library** (`src/shared/`)
  - `schemas.py` — Pydantic models for 9 event types and 3 severity levels
  - `constants.py` — centralized configuration and environment variable accessors
  - `logger.py` — Powertools Logger wrapper with correlation ID extraction
- **Unit tests** — 23 tests covering Producer (17) and Consumer (6) via pytest + moto
- **Integration test scaffold** — 4 tests for end-to-end LocalStack validation
- **Operational scripts**
  - `deploy.sh` — automated build, packaging, and Terraform orchestration
  - `load_test.sh` — configurable load testing with metrics
  - `seed_dlq.sh` — DLQ testing with intentionally malformed payloads
- **Makefile** — 20+ targets for the full development lifecycle
- **Docker Compose** — LocalStack 4.4.0 (community edition, no auth token required)
- **Project configuration** — `pyproject.toml` with ruff, pytest, mypy, and coverage settings
- **Apache License 2.0**

### Technical Decisions

- **API Gateway v1 over v2** — LocalStack community edition does not support `apigatewayv2`; REST API v1 is fully emulated and free-tier eligible on real AWS
- **LocalStack 4.4.0 pinned** — versions ≥2025 require `LOCALSTACK_AUTH_TOKEN` even for the free tier; 4.4.0 is the last version that runs without authentication
- **boto3 excluded from Lambda zip** — reduces package size from 27MB to 5.2MB, eliminating cold-start timeouts in LocalStack; boto3 is included in the AWS Lambda runtime
- **`LAMBDA_RUNTIME_ENVIRONMENT_TIMEOUT=180`** — extended from the default to accommodate initial container provisioning in resource-constrained environments

[0.1.0]: https://github.com/soneylegal/cortex/releases/tag/v0.1.0
