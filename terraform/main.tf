# ──────────────────────────────────────────────
# Orchestration — locals and data sources
# ──────────────────────────────────────────────
# Individual resources are defined in their own files:
#   - lambda.tf       (Lambda functions + IAM + packaging)
#   - sqs.tf          (Main queue + DLQ)
#   - dynamodb.tf     (Events table)
#   - api_gateway.tf  (HTTP API v2 + routes)
#
# This file contains shared data sources and locals
# that are referenced across multiple resource files.
# ──────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
