# ══════════════════════════════════════════════
#  Cortex — Serverless Data Pipeline
#  Makefile for development, testing, and deploy
# ══════════════════════════════════════════════

.DEFAULT_GOAL := help
.PHONY: help install lint format test test-integration \
        localstack-up localstack-down deploy-local deploy \
        plan destroy load-test seed-dlq clean

SHELL := /bin/bash
PROJECT_ROOT := $(shell pwd)
TERRAFORM_DIR := $(PROJECT_ROOT)/terraform

# ──────────────────────────────────────────────
# Help
# ──────────────────────────────────────────────

help: ## Show this help message
	@echo ""
	@echo "  Cortex — Serverless Data Pipeline"
	@echo "  ──────────────────────────────────"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ──────────────────────────────────────────────
# Development
# ──────────────────────────────────────────────

install: ## Install Python dev dependencies
	pip install -e ".[dev]"

lint: ## Run linter (ruff check + format check)
	ruff check src/ tests/
	ruff format --check src/ tests/

format: ## Auto-format code with ruff
	ruff format src/ tests/
	ruff check --fix src/ tests/

typecheck: ## Run mypy type checking
	mypy src/

# ──────────────────────────────────────────────
# Testing
# ──────────────────────────────────────────────

test: ## Run unit tests
	python -m pytest tests/unit/ -v --tb=short

test-cov: ## Run unit tests with coverage
	python -m pytest tests/unit/ -v --cov=src --cov-report=term-missing

test-integration: ## Run integration tests (requires LocalStack)
	python -m pytest tests/integration/ -v -m integration --tb=short

test-all: test test-integration ## Run all tests

# ──────────────────────────────────────────────
# LocalStack
# ──────────────────────────────────────────────

localstack-up: ## Start LocalStack via Docker Compose
	docker compose up -d
	@echo "Waiting for LocalStack to be ready..."
	@for i in $$(seq 1 30); do \
		if curl -sf http://localhost:4566/_localstack/health > /dev/null 2>&1; then \
			echo "✓ LocalStack is ready"; \
			exit 0; \
		fi; \
		echo "  Attempt $$i/30 — waiting..."; \
		sleep 3; \
	done; \
	echo "✗ LocalStack failed to start. Check logs: make localstack-logs"; \
	exit 1

localstack-down: ## Stop LocalStack
	docker compose down

localstack-logs: ## Tail LocalStack logs
	docker compose logs -f localstack

localstack-status: ## Check LocalStack health
	@curl -s http://localhost:4566/_localstack/health | python3 -m json.tool

# ──────────────────────────────────────────────
# Deploy
# ──────────────────────────────────────────────

deploy-local: ## Build + deploy to LocalStack
	@chmod +x scripts/deploy.sh
	./scripts/deploy.sh --local --auto-approve

deploy: ## Build + deploy to real AWS
	@chmod +x scripts/deploy.sh
	./scripts/deploy.sh

plan: ## Terraform plan (dry-run)
	cd $(TERRAFORM_DIR) && terraform plan

plan-local: ## Terraform plan for LocalStack
	cd $(TERRAFORM_DIR) && terraform plan -var="use_localstack=true"

destroy: ## Destroy all infrastructure
	@chmod +x scripts/deploy.sh
	./scripts/deploy.sh --destroy --auto-approve

destroy-local: ## Destroy LocalStack infrastructure
	@chmod +x scripts/deploy.sh
	./scripts/deploy.sh --local --destroy --auto-approve

# ──────────────────────────────────────────────
# Terraform utilities
# ──────────────────────────────────────────────

tf-init: ## Initialize Terraform
	cd $(TERRAFORM_DIR) && terraform init

tf-validate: ## Validate Terraform configuration
	cd $(TERRAFORM_DIR) && terraform validate

tf-fmt: ## Format Terraform files
	cd $(TERRAFORM_DIR) && terraform fmt -recursive

tf-output: ## Show Terraform outputs
	cd $(TERRAFORM_DIR) && terraform output

# ──────────────────────────────────────────────
# Load testing & DLQ
# ──────────────────────────────────────────────

load-test: ## Run load test (default: 10 requests to LocalStack)
	@chmod +x scripts/load_test.sh
	./scripts/load_test.sh

load-test-100: ## Run load test with 100 requests
	@chmod +x scripts/load_test.sh
	./scripts/load_test.sh --count 100

seed-dlq: ## Send invalid messages to test DLQ
	@chmod +x scripts/seed_dlq.sh
	./scripts/seed_dlq.sh

# ──────────────────────────────────────────────
# Cleanup
# ──────────────────────────────────────────────

clean: ## Remove build artifacts and caches
	rm -rf build/
	rm -rf dist/
	rm -rf *.egg-info
	rm -rf .pytest_cache
	rm -rf .mypy_cache
	rm -rf .ruff_cache
	rm -rf htmlcov
	rm -f .coverage
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@echo "✓ Clean complete"
