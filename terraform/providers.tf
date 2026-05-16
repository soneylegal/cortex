# ──────────────────────────────────────────────
# AWS Provider — toggleable between real AWS and LocalStack
# ──────────────────────────────────────────────
# Usage:
#   Real AWS:    terraform apply
#   LocalStack:  terraform apply -var="use_localstack=true"
# ──────────────────────────────────────────────

provider "aws" {
  region     = var.aws_region
  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null

  # Required for LocalStack — skip real AWS validation
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  s3_use_path_style           = var.use_localstack

  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      apigateway = var.localstack_endpoint
      cloudwatch = var.localstack_endpoint
      dynamodb   = var.localstack_endpoint
      iam        = var.localstack_endpoint
      lambda     = var.localstack_endpoint
      logs       = var.localstack_endpoint
      sns        = var.localstack_endpoint
      sqs        = var.localstack_endpoint
      sts        = var.localstack_endpoint
      s3         = var.localstack_endpoint
      glue       = var.localstack_endpoint
      events     = var.localstack_endpoint
      firehose   = var.localstack_endpoint
      athena     = var.localstack_endpoint
    }
  }
}
