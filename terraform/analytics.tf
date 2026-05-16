# ──────────────────────────────────────────────
# Data Engineering & Analytics (Phase 4)
# ──────────────────────────────────────────────

# 1. S3 Bucket for Data Lake
resource "aws_s3_bucket" "datalake" {
  bucket        = "${var.project_name}-datalake-${data.aws_caller_identity.current.account_id}-${var.environment}"
  force_destroy = true
  tags          = local.common_tags
}


resource "aws_s3_bucket_server_side_encryption_configuration" "datalake" {
  bucket = aws_s3_bucket.datalake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 2. IAM Role for Kinesis Firehose
resource "aws_iam_role" "firehose" {
  name = "${var.project_name}-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "firehose.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy" "firehose_s3" {
  name = "${var.project_name}-firehose-s3-policy"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.datalake.arn,
          "${aws_s3_bucket.datalake.arn}/*"
        ]
      }
    ]
  })
}

# 3. Kinesis Data Firehose
resource "aws_kinesis_firehose_delivery_stream" "datalake" {
  name        = "${var.project_name}-stream-to-s3"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.datalake.arn

    # Store events grouped by year/month/day
    prefix              = "events/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"

    buffering_size     = 5
    buffering_interval = 60
  }

  tags = local.common_tags
}

# 4. EventBridge Rule to route to Firehose
resource "aws_cloudwatch_event_rule" "to_firehose" {
  name           = "${var.project_name}-rule-to-firehose"
  event_bus_name = aws_cloudwatch_event_bus.main.name
  description    = "Route cortex events to Kinesis Firehose for the Data Lake"

  event_pattern = jsonencode({
    "source" : [{ "prefix" : "cortex.producer." }]
  })
}

resource "aws_iam_role" "eventbridge_firehose" {
  name = "${var.project_name}-eventbridge-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_firehose" {
  name = "${var.project_name}-eventbridge-firehose-policy"
  role = aws_iam_role.eventbridge_firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "firehose:PutRecord*"
        Effect   = "Allow"
        Resource = aws_kinesis_firehose_delivery_stream.datalake.arn
      }
    ]
  })
}

resource "aws_cloudwatch_event_target" "firehose" {
  rule           = aws_cloudwatch_event_rule.to_firehose.name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  arn            = aws_kinesis_firehose_delivery_stream.datalake.arn
  role_arn       = aws_iam_role.eventbridge_firehose.arn

  # Forward the detail to Firehose (which is the actual EventRecord JSON)
  # Firehose needs newlines, so we append a newline using InputTransformer
  input_transformer {
    input_paths = {
      "detail" = "$.detail"
    }
    input_template = "<detail>\n"
  }
}

# 5. AWS Glue Database & Athena Workgroup
resource "aws_glue_catalog_database" "datalake" {
  count = var.use_localstack ? 0 : 1
  name  = "${var.project_name}_datalake"
}

resource "aws_athena_workgroup" "analytics" {
  count = var.use_localstack ? 0 : 1
  name  = "${var.project_name}-analytics"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.datalake.bucket}/athena-results/"
    }
  }

  tags = local.common_tags
}
