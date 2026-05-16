#!/usr/bin/env bash
# ──────────────────────────────────────────────
# Cortex — Seed DLQ test script
# Sends intentionally malformed messages to test DLQ behavior
# ──────────────────────────────────────────────
# Usage:
#   ./scripts/seed_dlq.sh              # Send to LocalStack
#   ./scripts/seed_dlq.sh --url URL    # Send to real API Gateway
# ──────────────────────────────────────────────

set -euo pipefail

API_URL="${CORTEX_API_URL:-http://localhost:4566/restapis}"
API_KEY=""
COUNT=5

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

while [[ $# -gt 0 ]]; do
    case $1 in
        --url)      API_URL="$2"; shift 2 ;;
        --api-key)  API_KEY="$2"; shift 2 ;;
        --count)    COUNT="$2"; shift 2 ;;
        --help|-h)  echo "Usage: $0 [--url URL] [--api-key KEY] [--count N]"; exit 0 ;;
        *)          echo "Unknown: $1"; exit 1 ;;
    esac
done

EVENTS_URL="${API_URL}/events"

# ──────────────────────────────────────────────
# Invalid payloads designed to fail at different stages
# ──────────────────────────────────────────────

declare -a INVALID_PAYLOADS=(
    # 1. Missing required field "source"
    '{"event_type": "cpu_usage", "data": {"cpu_percent": 50}}'

    # 2. Invalid event_type enum value
    '{"source": "test-server", "event_type": "invalid_type", "data": {}}'

    # 3. Empty body
    ''

    # 4. Not valid JSON
    'this is not json at all {{{}'

    # 5. Missing required field "data"
    '{"source": "test-server", "event_type": "cpu_usage"}'
)

declare -a DESCRIPTIONS=(
    "Missing 'source' field"
    "Invalid event_type enum"
    "Empty body"
    "Malformed JSON"
    "Missing 'data' field"
)

log_info "Sending ${COUNT} invalid payloads to test error handling..."
log_info "Target: ${EVENTS_URL}"
echo ""

for i in $(seq 0 $((${#INVALID_PAYLOADS[@]} - 1))); do
    if [[ $i -ge $COUNT ]]; then
        break
    fi

    payload="${INVALID_PAYLOADS[$i]}"
    desc="${DESCRIPTIONS[$i]}"

    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${EVENTS_URL}" \
        -H "Content-Type: application/json" \
        ${API_KEY:+-H "x-api-key: ${API_KEY}"} \
        -d "${payload}" \
        --max-time 10 2>/dev/null || echo "000")

    if [[ "$http_code" =~ ^4 ]]; then
        echo -e "${GREEN}✓${NC} [${http_code}] ${desc} — Correctly rejected by Producer"
    elif [[ "$http_code" == "202" ]]; then
        echo -e "${YELLOW}⚠${NC} [${http_code}] ${desc} — Accepted (will fail at Consumer → DLQ)"
    else
        echo -e "${RED}✗${NC} [${http_code}] ${desc} — Unexpected response"
    fi
done

echo ""
log_info "Check the DLQ after ~${YELLOW}30 seconds${NC} (3 retries × Lambda timeout):"
log_warn "  awslocal sqs receive-message --queue-url \$(awslocal sqs get-queue-url --queue-name cortex-events-dlq --query QueueUrl --output text)"
