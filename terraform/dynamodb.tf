# ──────────────────────────────────────────────
# DynamoDB — Events table
# ──────────────────────────────────────────────

resource "aws_dynamodb_table" "events" {
  name         = "${var.project_name}-events"
  billing_mode = "PAY_PER_REQUEST" # On-demand — no provisioned capacity costs

  hash_key  = "event_id"
  range_key = "timestamp"

  attribute {
    name = "event_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  # TTL for automatic cleanup of old events (optional)
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = local.common_tags
}
