# ──────────────────────────────────────────────
# SQS — Main Queue + Dead Letter Queue
# ──────────────────────────────────────────────

# Dead Letter Queue — receives messages that failed maxReceiveCount times
resource "aws_sqs_queue" "dlq" {
  name                       = "${var.project_name}-events-dlq"
  message_retention_seconds  = var.sqs_message_retention
  visibility_timeout_seconds = var.sqs_visibility_timeout

  tags = local.common_tags
}

# Main Queue — receives events from the Producer Lambda
resource "aws_sqs_queue" "main" {
  name                       = "${var.project_name}-events-queue"
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = var.sqs_message_retention

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.dlq_max_receive_count
  })

  tags = local.common_tags
}

# Allow the main queue to send messages to the DLQ
resource "aws_sqs_queue_redrive_allow_policy" "dlq_allow" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main.arn]
  })
}
