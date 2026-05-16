# ──────────────────────────────────────────────
# Lambda — Producer + Consumer + IAM
# ──────────────────────────────────────────────

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ──────────────────────────────────────────────
# Package Lambda source code as .zip
# ──────────────────────────────────────────────

data "archive_file" "producer_zip" {
  type        = "zip"
  output_path = "${path.module}/../build/producer.zip"

  source {
    content  = file("${path.module}/../src/producer/handler.py")
    filename = "handler.py"
  }

  # Shared library files
  source {
    content  = file("${path.module}/../src/shared/__init__.py")
    filename = "shared/__init__.py"
  }
  source {
    content  = file("${path.module}/../src/shared/constants.py")
    filename = "shared/constants.py"
  }
  source {
    content  = file("${path.module}/../src/shared/schemas.py")
    filename = "shared/schemas.py"
  }
  source {
    content  = file("${path.module}/../src/shared/logger.py")
    filename = "shared/logger.py"
  }
}

data "archive_file" "consumer_zip" {
  type        = "zip"
  output_path = "${path.module}/../build/consumer.zip"

  source {
    content  = file("${path.module}/../src/consumer/handler.py")
    filename = "handler.py"
  }

  # Shared library files
  source {
    content  = file("${path.module}/../src/shared/__init__.py")
    filename = "shared/__init__.py"
  }
  source {
    content  = file("${path.module}/../src/shared/constants.py")
    filename = "shared/constants.py"
  }
  source {
    content  = file("${path.module}/../src/shared/schemas.py")
    filename = "shared/schemas.py"
  }
  source {
    content  = file("${path.module}/../src/shared/logger.py")
    filename = "shared/logger.py"
  }
}

# ──────────────────────────────────────────────
# IAM — Execution roles
# ──────────────────────────────────────────────

# Trust policy — allow Lambda service to assume the role
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# --- Producer IAM ---

resource "aws_iam_role" "producer" {
  name               = "${var.project_name}-producer-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "producer_policy" {
  # CloudWatch Logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # X-Ray Tracing
  statement {
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = ["*"]
  }

  # SQS — send messages to the main queue only
  statement {
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueUrl",
    ]
    resources = [aws_sqs_queue.main.arn]
  }
}

resource "aws_iam_role_policy" "producer" {
  name   = "${var.project_name}-producer-policy"
  role   = aws_iam_role.producer.id
  policy = data.aws_iam_policy_document.producer_policy.json
}

# --- Consumer IAM ---

resource "aws_iam_role" "consumer" {
  name               = "${var.project_name}-consumer-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "consumer_policy" {
  # CloudWatch Logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # X-Ray Tracing
  statement {
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = ["*"]
  }

  # SQS — receive, delete, get attributes from the main queue
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.main.arn]
  }

  # DynamoDB — write to the events table
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
    ]
    resources = [aws_dynamodb_table.events.arn]
  }
}

resource "aws_iam_role_policy" "consumer" {
  name   = "${var.project_name}-consumer-policy"
  role   = aws_iam_role.consumer.id
  policy = data.aws_iam_policy_document.consumer_policy.json
}

# ──────────────────────────────────────────────
# Lambda Functions
# ──────────────────────────────────────────────

resource "aws_lambda_function" "producer" {
  function_name = "${var.project_name}-producer"
  description   = "Cortex Producer — validates and enqueues infrastructure monitoring events"
  role          = aws_iam_role.producer.arn
  handler       = "handler.handler"
  runtime       = var.lambda_runtime
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  tracing_config {
    mode = "Active"
  }

  filename         = data.archive_file.producer_zip.output_path
  source_code_hash = data.archive_file.producer_zip.output_base64sha256

  environment {
    variables = {
      QUEUE_URL               = aws_sqs_queue.main.url
      POWERTOOLS_SERVICE_NAME = "${var.project_name}-producer"
      POWERTOOLS_LOG_LEVEL    = var.lambda_log_level
      LOG_LEVEL               = var.lambda_log_level
      CORTEX_API_KEY          = var.api_key
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_function" "consumer" {
  function_name = "${var.project_name}-consumer"
  description   = "Cortex Consumer — persists monitoring events from SQS to DynamoDB"
  role          = aws_iam_role.consumer.arn
  handler       = "handler.handler"
  runtime       = var.lambda_runtime
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  tracing_config {
    mode = "Active"
  }

  filename         = data.archive_file.consumer_zip.output_path
  source_code_hash = data.archive_file.consumer_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME              = aws_dynamodb_table.events.name
      POWERTOOLS_SERVICE_NAME = "${var.project_name}-consumer"
      POWERTOOLS_LOG_LEVEL    = var.lambda_log_level
      LOG_LEVEL               = var.lambda_log_level
    }
  }

  tags = local.common_tags
}

# ──────────────────────────────────────────────
# SQS → Consumer Event Source Mapping
# ──────────────────────────────────────────────

resource "aws_lambda_event_source_mapping" "sqs_to_consumer" {
  event_source_arn = aws_sqs_queue.main.arn
  function_name    = aws_lambda_function.consumer.arn
  enabled          = true

  batch_size                         = var.consumer_batch_size
  maximum_batching_window_in_seconds = var.consumer_batch_window

  # Report only failed messages — don't retry the entire batch
  function_response_types = ["ReportBatchItemFailures"]

  # Limit concurrency to protect DynamoDB
  scaling_config {
    maximum_concurrency = var.consumer_max_concurrency
  }
}
