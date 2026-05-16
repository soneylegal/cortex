# ──────────────────────────────────────────────
# Authorizer Lambda
# ──────────────────────────────────────────────

data "archive_file" "authorizer_zip" {
  type        = "zip"
  output_path = "${path.module}/../build/authorizer.zip"

  source {
    content  = file("${path.module}/../src/authorizer/handler.py")
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

resource "aws_iam_role" "authorizer" {
  name               = "${var.project_name}-authorizer-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "authorizer_policy" {
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
}

resource "aws_iam_role_policy" "authorizer" {
  name   = "${var.project_name}-authorizer-policy"
  role   = aws_iam_role.authorizer.id
  policy = data.aws_iam_policy_document.authorizer_policy.json
}

resource "aws_lambda_function" "authorizer" {
  function_name = "${var.project_name}-authorizer"
  description   = "Cortex Authorizer — validates JWT tokens"
  role          = aws_iam_role.authorizer.arn
  handler       = "handler.handler"
  runtime       = var.lambda_runtime
  memory_size   = 128
  timeout       = 10

  tracing_config {
    mode = "Active"
  }

  filename         = data.archive_file.authorizer_zip.output_path
  source_code_hash = data.archive_file.authorizer_zip.output_base64sha256

  environment {
    variables = {
      JWT_SECRET              = var.jwt_secret
      POWERTOOLS_SERVICE_NAME = "${var.project_name}-authorizer"
      POWERTOOLS_LOG_LEVEL    = var.lambda_log_level
    }
  }

  tags = local.common_tags
}
