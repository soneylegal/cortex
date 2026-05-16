# ──────────────────────────────────────────────
# General
# ──────────────────────────────────────────────

variable "project_name" {
  description = "Prefix for all AWS resource names"
  type        = string
  default     = "cortex"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

# ──────────────────────────────────────────────
# LocalStack
# ──────────────────────────────────────────────

variable "use_localstack" {
  description = "When true, point all AWS calls to LocalStack at localhost:4566"
  type        = bool
  default     = false
}

variable "localstack_endpoint" {
  description = "LocalStack edge endpoint URL"
  type        = string
  default     = "http://localhost:4566"
}

# ──────────────────────────────────────────────
# Lambda
# ──────────────────────────────────────────────

variable "lambda_memory_size" {
  description = "Memory (MB) allocated to each Lambda function"
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Timeout (seconds) for each Lambda function"
  type        = number
  default     = 30
}

variable "lambda_log_level" {
  description = "Log level for Lambda Powertools (DEBUG, INFO, WARNING, ERROR)"
  type        = string
  default     = "INFO"
}

variable "lambda_runtime" {
  description = "Python runtime version for Lambda functions"
  type        = string
  default     = "python3.12"
}

# ──────────────────────────────────────────────
# SQS
# ──────────────────────────────────────────────

variable "sqs_visibility_timeout" {
  description = "Visibility timeout (seconds) for the main queue. Should be >= 6× Lambda timeout."
  type        = number
  default     = 180
}

variable "sqs_message_retention" {
  description = "Message retention period (seconds). Max: 1209600 (14 days)."
  type        = number
  default     = 1209600
}

variable "dlq_max_receive_count" {
  description = "Number of times a message is received before being sent to the DLQ"
  type        = number
  default     = 3
}

# ──────────────────────────────────────────────
# SQS Consumer batching
# ──────────────────────────────────────────────

variable "consumer_batch_size" {
  description = "Maximum number of SQS messages in a single Lambda invocation"
  type        = number
  default     = 10
}

variable "consumer_batch_window" {
  description = "Maximum seconds to wait for a full batch before invoking Lambda"
  type        = number
  default     = 5
}

variable "consumer_max_concurrency" {
  description = "Maximum concurrent Lambda consumers (protects DynamoDB)"
  type        = number
  default     = 5
}

# ──────────────────────────────────────────────
# API Key (optional — empty = open mode)
# ──────────────────────────────────────────────

variable "api_key" {
  description = "API key for x-api-key header validation. Leave empty for open mode."
  type        = string
  default     = ""
  sensitive   = true
}

# ──────────────────────────────────────────────
# Security (Phase 3)
# ──────────────────────────────────────────────

variable "jwt_secret" {
  description = "Secret key used to validate JWT signatures"
  type        = string
  default     = "default-secret-key-for-local-dev"
  sensitive   = true
}
