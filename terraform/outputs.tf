# ──────────────────────────────────────────────
# Outputs — useful references after terraform apply
# ──────────────────────────────────────────────

output "api_endpoint" {
  description = "Base URL of the Cortex REST API"
  value       = aws_api_gateway_stage.dev.invoke_url
}

output "api_events_url" {
  description = "Full URL for the POST /events endpoint"
  value       = "${aws_api_gateway_stage.dev.invoke_url}/events"
}

output "queue_url" {
  description = "URL of the main SQS queue"
  value       = aws_sqs_queue.main.url
}

output "dlq_url" {
  description = "URL of the Dead Letter Queue"
  value       = aws_sqs_queue.dlq.url
}

output "table_name" {
  description = "Name of the DynamoDB events table"
  value       = aws_dynamodb_table.events.name
}

output "producer_function_name" {
  description = "Name of the Producer Lambda function"
  value       = aws_lambda_function.producer.function_name
}

output "consumer_function_name" {
  description = "Name of the Consumer Lambda function"
  value       = aws_lambda_function.consumer.function_name
}

output "producer_function_arn" {
  description = "ARN of the Producer Lambda function"
  value       = aws_lambda_function.producer.arn
}

output "consumer_function_arn" {
  description = "ARN of the Consumer Lambda function"
  value       = aws_lambda_function.consumer.arn
}
