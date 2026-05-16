# CHANGELOG


## v0.2.0 (2026-05-16)

### Bug Fixes

* fix(tests): restore wiped handlers, migrate producer to EventBridge and resolve pathing scopes ([`ec2ee0e`](https://github.com/soneylegal/cortex/commit/ec2ee0e2a3e12ea56b6ac37965dc824787c3bc95))

### Continuous Integration

* ci: configure github actions, linting and semantic release ([`f0c15b9`](https://github.com/soneylegal/cortex/commit/f0c15b91fa5fdbf3ddbadb1ce7f64aa696c29d14))

### Features

* feat(api): create containerized fastapi read microservice via serverless lambda ([`828b091`](https://github.com/soneylegal/cortex/commit/828b091268832c80f3c2f08964788af4aac9bb2e))

* feat(analytics): implement eventbridge fan-out to kinesis firehose and athena data lake ([`3db53cd`](https://github.com/soneylegal/cortex/commit/3db53cde359c3d341d388486124ba710e8b85050))

* feat(security): implement lambda custom authorizer and api gateway rate limiting ([`cb48b0d`](https://github.com/soneylegal/cortex/commit/cb48b0db72bd709ffd58ce813e0c54a9c245a78b))

* feat(observability): enable aws x-ray tracing and provision cloudwatch dashboards ([`6c15a8f`](https://github.com/soneylegal/cortex/commit/6c15a8f3de2494b14550d52712ee744d06b2e058))


## v0.1.0 (2026-05-16)

### Breaking

* feat: initial serverless data pipeline architecture

Implement Cortex v0.1.0 — a resilient, cloud-native data pipeline for
infrastructure monitoring built on AWS serverless primitives.

Architecture:
- API Gateway (REST v1) → Lambda Producer → SQS → Lambda Consumer → DynamoDB
- Dead Letter Queue with maxReceiveCount=3 for automatic error redirection
- ReportBatchItemFailures for partial batch failure handling
- Idempotent DynamoDB writes via ConditionExpression

Components:
- Producer Lambda: Pydantic schema validation, optional x-api-key auth,
  payload enrichment with request metadata, SQS dispatch
- Consumer Lambda: SQS batch processing, DynamoDB persistence,
  duplicate detection, structured error reporting
- Shared library: Powertools logger, Pydantic models (9 event types),
  centralized constants and environment variable accessors

Infrastructure as Code:
- 9 Terraform files with LocalStack toggle (-var=use_localstack=true)
- REST API v1 (LocalStack community compatible)
- On-demand DynamoDB with TTL support
- IAM roles with least-privilege policies

Testing & Tooling:
- 23 unit tests (pytest + moto) — all passing
- Integration test scaffold for LocalStack E2E validation
- Makefile with 20+ targets for full development lifecycle
- Docker Compose with LocalStack 4.4.0 (no auth token required)
- Operational scripts: deploy, load test, DLQ seeding

BREAKING CHANGE: none (initial release) ([`f3ef56b`](https://github.com/soneylegal/cortex/commit/f3ef56b26fac68e6e9ef3eb56ac2bd31f2ce21f8))
