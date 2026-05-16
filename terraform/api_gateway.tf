# ──────────────────────────────────────────────
# API Gateway — REST API (v1)
# ──────────────────────────────────────────────
# Using REST API (v1) instead of HTTP API (v2) because
# LocalStack community edition only supports apigateway v1.
# For production on real AWS, consider migrating to HTTP API v2
# for lower latency and cost.
# ──────────────────────────────────────────────

resource "aws_api_gateway_rest_api" "cortex" {
  name        = "${var.project_name}-api"
  description = "Cortex — Infrastructure Monitoring Data Pipeline API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

# Resource: /events
resource "aws_api_gateway_resource" "events" {
  rest_api_id = aws_api_gateway_rest_api.cortex.id
  parent_id   = aws_api_gateway_rest_api.cortex.root_resource_id
  path_part   = "events"
}

# ──────────────────────────────────────────────
# Authorizer Integration
# ──────────────────────────────────────────────

resource "aws_api_gateway_authorizer" "jwt" {
  name                   = "${var.project_name}-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.cortex.id
  authorizer_uri         = aws_lambda_function.authorizer.invoke_arn
  authorizer_credentials = aws_iam_role.invocation_role.arn
  type                   = "TOKEN"
}

# IAM Role for API Gateway to invoke Authorizer
resource "aws_iam_role" "invocation_role" {
  name = "${var.project_name}-api-gateway-auth-invoke"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "invocation_policy" {
  name = "${var.project_name}-api-gateway-auth-invoke-policy"
  role = aws_iam_role.invocation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "lambda:InvokeFunction"
        Effect   = "Allow"
        Resource = aws_lambda_function.authorizer.arn
      }
    ]
  })
}

# Method: POST /events
resource "aws_api_gateway_method" "post_events" {
  rest_api_id   = aws_api_gateway_rest_api.cortex.id
  resource_id   = aws_api_gateway_resource.events.id
  http_method   = "POST"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.jwt.id
}

# Lambda integration — proxy to Producer
resource "aws_api_gateway_integration" "producer" {
  rest_api_id             = aws_api_gateway_rest_api.cortex.id
  resource_id             = aws_api_gateway_resource.events.id
  http_method             = aws_api_gateway_method.post_events.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.producer.invoke_arn
}

# Deploy the API
resource "aws_api_gateway_deployment" "cortex" {
  rest_api_id = aws_api_gateway_rest_api.cortex.id

  depends_on = [
    aws_api_gateway_integration.producer,
  ]

  # Force redeployment when integration changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.events.id,
      aws_api_gateway_method.post_events.id,
      aws_api_gateway_integration.producer.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Stage: dev
resource "aws_api_gateway_stage" "dev" {
  deployment_id        = aws_api_gateway_deployment.cortex.id
  rest_api_id          = aws_api_gateway_rest_api.cortex.id
  stage_name           = var.environment
  xray_tracing_enabled = true

  tags = local.common_tags
}

# Allow API Gateway to invoke the Producer Lambda
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.cortex.execution_arn}/*/*"
}

# ──────────────────────────────────────────────
# Rate Limiting & Usage Plan
# ──────────────────────────────────────────────

resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.project_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.cortex.id
    stage  = aws_api_gateway_stage.dev.stage_name
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 10000
    offset = 0
    period = "DAY"
  }
}
