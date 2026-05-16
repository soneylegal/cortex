# ──────────────────────────────────────────────
# Read API (FastAPI serverless deployment)
# ──────────────────────────────────────────────

data "archive_file" "read_api_zip" {
  type        = "zip"
  output_path = "${path.module}/../build/read_api.zip"

  source {
    content  = file("${path.module}/../src/api/main.py")
    filename = "main.py"
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

resource "aws_iam_role" "read_api" {
  name               = "${var.project_name}-read-api-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "read_api_policy" {
  # CloudWatch Logs & X-Ray
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = ["*"]
  }

  # DynamoDB Read Access
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [aws_dynamodb_table.events.arn]
  }
}

resource "aws_iam_role_policy" "read_api" {
  name   = "${var.project_name}-read-api-policy"
  role   = aws_iam_role.read_api.id
  policy = data.aws_iam_policy_document.read_api_policy.json
}

resource "aws_lambda_function" "read_api" {
  function_name = "${var.project_name}-read-api"
  description   = "Cortex Read API — FastAPI microservice for querying events"
  role          = aws_iam_role.read_api.arn
  handler       = "main.handler" # Mangum handler
  runtime       = var.lambda_runtime
  memory_size   = 256
  timeout       = 10

  tracing_config {
    mode = "Active"
  }

  filename         = data.archive_file.read_api_zip.output_path
  source_code_hash = data.archive_file.read_api_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME              = aws_dynamodb_table.events.name
      POWERTOOLS_SERVICE_NAME = "${var.project_name}-read-api"
      POWERTOOLS_LOG_LEVEL    = var.lambda_log_level
    }
  }

  tags = local.common_tags
}

# API Gateway Integration (REST API)
resource "aws_api_gateway_resource" "events_read" {
  rest_api_id = aws_api_gateway_rest_api.cortex.id
  parent_id   = aws_api_gateway_resource.events.id
  path_part   = "{event_id}"
}

resource "aws_api_gateway_resource" "events_read_timestamp" {
  rest_api_id = aws_api_gateway_rest_api.cortex.id
  parent_id   = aws_api_gateway_resource.events_read.id
  path_part   = "{timestamp}"
}

resource "aws_api_gateway_method" "get_events" {
  rest_api_id   = aws_api_gateway_rest_api.cortex.id
  resource_id   = aws_api_gateway_resource.events_read_timestamp.id
  http_method   = "GET"
  authorization = "NONE" # For simplicity on the Read API
}

resource "aws_api_gateway_integration" "read_api" {
  rest_api_id             = aws_api_gateway_rest_api.cortex.id
  resource_id             = aws_api_gateway_resource.events_read_timestamp.id
  http_method             = aws_api_gateway_method.get_events.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.read_api.invoke_arn
}

resource "aws_lambda_permission" "api_gateway_read_invoke" {
  statement_id  = "AllowAPIGatewayInvokeReadAPI"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.read_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.cortex.execution_arn}/*/*"
}
