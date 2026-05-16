#!/usr/bin/env bash
# ──────────────────────────────────────────────
# Cortex — Load test script
# Sends concurrent requests to the API Gateway
# ──────────────────────────────────────────────
# Usage:
#   ./scripts/load_test.sh                          # 10 requests to LocalStack
#   ./scripts/load_test.sh --count 100              # 100 requests
#   ./scripts/load_test.sh --url https://xxx.execute-api.us-east-1.amazonaws.com
#   ./scripts/load_test.sh --api-key my-secret-key
# ──────────────────────────────────────────────

set -euo pipefail

# Defaults
API_URL="${CORTEX_API_URL:-http://localhost:4566/restapis}"
REQUEST_COUNT=10
CONCURRENCY=5
API_KEY=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }

# ──────────────────────────────────────────────
# Parse arguments
# ──────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --url)       API_URL="$2"; shift 2 ;;
        --count)     REQUEST_COUNT="$2"; shift 2 ;;
        --concurrency) CONCURRENCY="$2"; shift 2 ;;
        --api-key)   API_KEY="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--url URL] [--count N] [--concurrency N] [--api-key KEY]"
            exit 0
            ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

# ──────────────────────────────────────────────
# Generate sample payloads
# ──────────────────────────────────────────────

SOURCES=("server-web-01" "server-web-02" "server-db-01" "server-cache-01" "server-worker-01")
EVENT_TYPES=("cpu_usage" "memory_usage" "disk_io" "network_latency" "health_check")
SEVERITIES=("info" "warning" "critical")

generate_payload() {
    local source="${SOURCES[$((RANDOM % ${#SOURCES[@]}))]}"
    local event_type="${EVENT_TYPES[$((RANDOM % ${#EVENT_TYPES[@]}))]}"
    local severity="${SEVERITIES[$((RANDOM % ${#SEVERITIES[@]}))]}"
    local cpu=$((RANDOM % 100))
    local memory=$((RANDOM % 100))

    cat <<EOF
{
    "source": "${source}",
    "event_type": "${event_type}",
    "severity": "${severity}",
    "data": {
        "cpu_percent": ${cpu}.${RANDOM:0:1},
        "memory_percent": ${memory}.${RANDOM:0:1},
        "load_avg_1m": $((RANDOM % 10)).$((RANDOM % 99)),
        "uptime_seconds": $((RANDOM * RANDOM))
    },
    "hostname": "${source}.internal",
    "region": "us-east-1",
    "tags": {
        "env": "load-test",
        "team": "platform"
    }
}
EOF
}

# ──────────────────────────────────────────────
# Execute load test
# ──────────────────────────────────────────────

EVENTS_URL="${API_URL}/events"
log_info "Target:      ${EVENTS_URL}"
log_info "Requests:    ${REQUEST_COUNT}"
log_info "Concurrency: ${CONCURRENCY}"
echo ""

SUCCESS=0
FAILURE=0
TOTAL_TIME=0
START_TIME=$(date +%s%N)

# Build extra headers
HEADERS=""
if [[ -n "$API_KEY" ]]; then
    HEADERS="-H 'x-api-key: ${API_KEY}'"
fi

send_request() {
    local payload
    payload=$(generate_payload)
    local start end duration http_code

    start=$(date +%s%N)
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${EVENTS_URL}" \
        -H "Content-Type: application/json" \
        ${HEADERS:+-H "x-api-key: ${API_KEY}"} \
        -d "${payload}" \
        --max-time 10 2>/dev/null || echo "000")
    end=$(date +%s%N)
    duration=$(( (end - start) / 1000000 ))  # ms

    if [[ "$http_code" == "202" ]]; then
        echo -e "${GREEN}✓${NC} ${http_code} (${duration}ms)"
        return 0
    else
        echo -e "${RED}✗${NC} ${http_code} (${duration}ms)"
        return 1
    fi
}

export -f send_request generate_payload
export API_URL EVENTS_URL API_KEY HEADERS GREEN RED NC
export SOURCES EVENT_TYPES SEVERITIES

# Run requests with controlled concurrency
for i in $(seq 1 "${REQUEST_COUNT}"); do
    if send_request; then
        SUCCESS=$((SUCCESS + 1))
    else
        FAILURE=$((FAILURE + 1))
    fi
done

END_TIME=$(date +%s%N)
ELAPSED=$(( (END_TIME - START_TIME) / 1000000 ))

# ──────────────────────────────────────────────
# Results
# ──────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════"
echo "  Load Test Results"
echo "═══════════════════════════════════════"
echo -e "  Total:     ${REQUEST_COUNT}"
echo -e "  ${GREEN}Success:   ${SUCCESS}${NC}"
echo -e "  ${RED}Failed:    ${FAILURE}${NC}"
echo -e "  Duration:  ${ELAPSED}ms"
if [[ $ELAPSED -gt 0 ]]; then
    RPS=$(( REQUEST_COUNT * 1000 / ELAPSED ))
    echo -e "  Throughput: ~${RPS} req/s"
fi
echo "═══════════════════════════════════════"
