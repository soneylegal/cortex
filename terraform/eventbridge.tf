# ──────────────────────────────────────────────
# EventBridge
# ──────────────────────────────────────────────

resource "aws_cloudwatch_event_bus" "main" {
  name = "${var.project_name}-events-bus"
  tags = local.common_tags
}

# Rule: All events go to SQS for DynamoDB
resource "aws_cloudwatch_event_rule" "to_sqs" {
  name           = "${var.project_name}-rule-to-sqs"
  event_bus_name = aws_cloudwatch_event_bus.main.name
  description    = "Route all cortex events to the main SQS queue"

  # Match any event sent by the Producer
  event_pattern = jsonencode({
    "source" : [{ "prefix" : "cortex.producer." }]
  })
}

resource "aws_cloudwatch_event_target" "sqs" {
  rule           = aws_cloudwatch_event_rule.to_sqs.name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  arn            = aws_sqs_queue.main.arn

  # Extract the detail part so the SQS message looks exactly like the old payload
  input_path = "$.detail"
}

# SQS Policy to allow EventBridge to send messages
resource "aws_sqs_queue_policy" "eventbridge_to_sqs" {
  queue_url = aws_sqs_queue.main.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.main.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.to_sqs.arn
          }
        }
      }
    ]
  })
}
