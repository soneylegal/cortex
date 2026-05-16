#!/usr/bin/env bash
# ──────────────────────────────────────────────
# Cortex — Deploy script
# Packages Lambda functions and runs Terraform
# ──────────────────────────────────────────────
# Usage:
#   ./scripts/deploy.sh              # Deploy to real AWS
#   ./scripts/deploy.sh --local      # Deploy to LocalStack
#   ./scripts/deploy.sh --destroy    # Tear down infrastructure
# ──────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
BUILD_DIR="${PROJECT_ROOT}/build"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ──────────────────────────────────────────────
# Parse arguments
# ──────────────────────────────────────────────
USE_LOCALSTACK=false
DESTROY=false
AUTO_APPROVE=false

for arg in "$@"; do
    case $arg in
        --local)      USE_LOCALSTACK=true ;;
        --destroy)    DESTROY=true ;;
        --auto-approve) AUTO_APPROVE=true ;;
        --help|-h)
            echo "Usage: $0 [--local] [--destroy] [--auto-approve]"
            echo ""
            echo "  --local         Deploy to LocalStack instead of real AWS"
            echo "  --destroy       Tear down all infrastructure"
            echo "  --auto-approve  Skip terraform approval prompt"
            exit 0
            ;;
        *)
            log_error "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

# ──────────────────────────────────────────────
# Pre-flight checks
# ──────────────────────────────────────────────
log_info "Running pre-flight checks..."

if ! command -v terraform &>/dev/null; then
    log_error "Terraform is not installed. Install: https://developer.hashicorp.com/terraform/install"
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    log_error "Python 3 is not installed."
    exit 1
fi

if $USE_LOCALSTACK; then
    if ! curl -s http://localhost:4566/_localstack/health &>/dev/null; then
        log_error "LocalStack is not running. Start with: docker compose up -d"
        exit 1
    fi
    log_ok "LocalStack is healthy"
fi

# ──────────────────────────────────────────────
# Build Lambda packages
# ──────────────────────────────────────────────
if ! $DESTROY; then
    log_info "Creating build directory..."
    mkdir -p "${BUILD_DIR}"

    for LAMBDA in producer consumer; do
        log_info "Packaging ${LAMBDA} Lambda..."
        LAMBDA_BUILD="${BUILD_DIR}/${LAMBDA}_pkg"
        rm -rf "${LAMBDA_BUILD}"
        mkdir -p "${LAMBDA_BUILD}"

        # Install dependencies
        pip3 install -q \
            -r "${PROJECT_ROOT}/src/${LAMBDA}/requirements.txt" \
            -t "${LAMBDA_BUILD}" \
            --upgrade \
            --no-cache-dir 2>/dev/null

        # Copy handler and shared library
        cp "${PROJECT_ROOT}/src/${LAMBDA}/handler.py" "${LAMBDA_BUILD}/"
        cp -r "${PROJECT_ROOT}/src/shared" "${LAMBDA_BUILD}/shared"

        log_ok "${LAMBDA} packaged at ${LAMBDA_BUILD}"
    done
fi

# ──────────────────────────────────────────────
# Terraform
# ──────────────────────────────────────────────
log_info "Initializing Terraform..."
cd "${TERRAFORM_DIR}"

terraform init -input=false

TF_VARS=""
if $USE_LOCALSTACK; then
    TF_VARS="-var=use_localstack=true"
    log_warn "Deploying to LocalStack (http://localhost:4566)"
else
    log_warn "Deploying to REAL AWS account"
fi

APPROVE_FLAG=""
if $AUTO_APPROVE; then
    APPROVE_FLAG="-auto-approve"
fi

if $DESTROY; then
    log_warn "Destroying all Cortex infrastructure..."
    terraform destroy ${TF_VARS} ${APPROVE_FLAG}
    log_ok "Infrastructure destroyed"
else
    log_info "Planning infrastructure changes..."
    terraform plan ${TF_VARS} -out=tfplan

    log_info "Applying infrastructure..."
    terraform apply ${APPROVE_FLAG} tfplan

    rm -f tfplan

    echo ""
    log_ok "═══════════════════════════════════════"
    log_ok "  Cortex deployed successfully! 🚀"
    log_ok "═══════════════════════════════════════"
    echo ""
    terraform output
fi
