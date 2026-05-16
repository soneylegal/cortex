# 🧠 Cortex — Serverless Data Pipeline

> Pipeline de dados serverless para **Monitoramento de Infraestrutura**, construído com foco em **Resiliência**, **Cloud Nativo** e **Infrastructure as Code**.

```
User → API Gateway (REST) → Lambda Producer → SQS → Lambda Consumer → DynamoDB
                                                ↓ (falhas)
                                               DLQ
```

---

## 📌 Development Status

| Dimensão | Estado |
|---|---|
| **Release** | `v0.1.0` — Initial Architecture |
| **Pipeline** | ✅ API Gateway → Producer → SQS (validado E2E no LocalStack) |
| **Consumer** | ✅ Lógica implementada e testada unitariamente (23/23 testes) |
| **IaC** | ✅ Terraform apply completo — 18 recursos provisionados |
| **Lint** | ✅ `ruff check` + `ruff format` — zero warnings |
| **Licença** | Apache License 2.0 |

## 🔬 Engineering Notes

<details>
<summary><strong>Decisões Técnicas & Trade-offs</strong></summary>

### API Gateway v1 (REST) vs v2 (HTTP)

O plano original usava HTTP API (v2) por ser mais leve e barato. Durante o deploy no LocalStack, identificamos que **`apigatewayv2` não é suportado na edição community**. A migração para REST API (v1) foi feita sem perda funcional — v1 é fully emulated no LocalStack e elegível ao Free Tier da AWS.

### Lambda Package Size: 27MB → 5.2MB

O pacote inicial incluía `boto3` + `botocore` (~22MB), que **já estão disponíveis no runtime do Lambda**. Excluí-los reduziu o zip de 27MB para 5.2MB, eliminando timeouts de cold-start no LocalStack e melhorando o tempo de deploy.

### LocalStack 4.4.0 (pinned)

A partir de 2025, o LocalStack exige `LOCALSTACK_AUTH_TOKEN` mesmo no tier gratuito. A versão 4.4.0 é a última que opera sem autenticação. Para usar a versão mais recente, basta criar uma conta gratuita em [app.localstack.cloud](https://app.localstack.cloud) e configurar o token no `docker-compose.yml`.

### Idempotência no DynamoDB

O Consumer usa `ConditionExpression` (`attribute_not_exists(event_id) AND attribute_not_exists(timestamp)`) para garantir que mensagens reprocessadas pelo SQS não gerem duplicatas. Isso é essencial quando combinado com `ReportBatchItemFailures`, que pode re-entregar mensagens individuais de um batch.

### Empty API Key = Open Mode

A variável `CORTEX_API_KEY` quando vazia (`""`) é tratada como `None` (modo aberto). Isso permite deploy sem autenticação por padrão, com ativação via `terraform apply -var="api_key=..."`.

</details>

---

## ⚡ Stack

| Camada | Tecnologia |
|---|---|
| **Ingestão** | AWS API Gateway (REST API v1) |
| **Validação** | AWS Lambda (Python 3.12) + Pydantic |
| **Mensageria** | AWS SQS + Dead Letter Queue |
| **Processamento** | AWS Lambda (Consumer) |
| **Persistência** | AWS DynamoDB (on-demand) |
| **IaC** | Terraform (HCL) |
| **Dev Local** | LocalStack 4.4.0 + Docker Compose |
| **Observabilidade** | AWS Lambda Powertools (structured logging) |

## 📁 Estrutura

```
cortex/
├── src/
│   ├── producer/       # Lambda — validação + envio para SQS
│   ├── consumer/       # Lambda — processamento + DynamoDB
│   └── shared/         # Logger, schemas, constantes
├── terraform/          # Infra completa (9 arquivos .tf)
├── scripts/            # Deploy, load test, seed DLQ
├── tests/
│   ├── unit/           # Testes unitários (mock)
│   └── integration/    # Testes e2e (LocalStack)
├── docker-compose.yml  # LocalStack
├── Makefile            # 20+ targets
├── pyproject.toml      # Deps + config (ruff, pytest, mypy)
├── CHANGELOG.md        # Histórico de releases
└── LICENSE             # Apache License 2.0
```

## 🚀 Quick Start

### Pré-requisitos

- Python 3.12+
- Docker & Docker Compose
- Terraform >= 1.5

### 1. Instalar dependências

```bash
pip install -e ".[dev]"
```

### 2. Rodar testes unitários

```bash
make test
```

### 3. Deploy local (LocalStack)

```bash
make localstack-up      # Sobe o LocalStack
make deploy-local       # Empacota Lambdas + terraform apply
```

### 4. Testar o pipeline

```bash
# Enviar um evento válido
curl -X POST http://localhost:4566/restapis/<api-id>/dev/_user_request_/events \
  -H "Content-Type: application/json" \
  -d '{
    "source": "server-web-01",
    "event_type": "cpu_usage",
    "severity": "warning",
    "data": {"cpu_percent": 87.5, "load_avg_1m": 2.3}
  }'
```

### 5. Teste de carga

```bash
make load-test          # 10 requests
make load-test-100      # 100 requests
```

## 🛡️ Resiliência

| Mecanismo | Implementação |
|---|---|
| **Dead Letter Queue** | Mensagens que falham 3× vão para a DLQ |
| **Partial Batch Failure** | `ReportBatchItemFailures` — só re-processa mensagens que falharam |
| **Idempotência** | `ConditionExpression` no DynamoDB evita duplicatas |
| **Visibility Timeout** | 180s (6× Lambda timeout de 30s) |
| **Scaling Config** | `maximum_concurrency = 5` protege o DynamoDB |

## 🔑 Autenticação

O Producer Lambda suporta validação de API Key via header `x-api-key`:

```bash
# Sem autenticação (open mode — padrão)
curl -X POST .../events -d '...'

# Com API Key configurada (via Terraform variable)
terraform apply -var="api_key=minha-chave-secreta"
curl -X POST .../events -H "x-api-key: minha-chave-secreta" -d '...'
```

## 📋 Makefile Targets

```bash
make help             # Lista todos os targets
make install          # Instala dependências dev
make lint             # Ruff check + format check
make format           # Auto-format
make test             # Testes unitários
make test-integration # Testes e2e (LocalStack)
make localstack-up    # Sobe LocalStack
make deploy-local     # Deploy no LocalStack
make deploy           # Deploy na AWS real
make load-test        # Teste de carga
make seed-dlq         # Testa DLQ com payloads inválidos
make clean            # Limpa artifacts
```

## 🏗️ Terraform

```bash
make tf-init          # terraform init
make tf-validate      # terraform validate
make plan-local       # terraform plan (LocalStack)
make deploy-local     # terraform apply (LocalStack)
make destroy-local    # terraform destroy (LocalStack)
```

### Outputs após deploy

| Output | Descrição |
|---|---|
| `api_endpoint` | URL base do API Gateway |
| `api_events_url` | URL completa `POST /events` |
| `queue_url` | URL da fila SQS principal |
| `dlq_url` | URL da Dead Letter Queue |
| `table_name` | Nome da tabela DynamoDB |

## 📊 Schema — Infrastructure Monitoring

```json
{
  "source": "server-web-01",
  "event_type": "cpu_usage",
  "severity": "warning",
  "data": {
    "cpu_percent": 87.5,
    "load_avg_1m": 2.3,
    "cores": 4
  },
  "hostname": "ip-10-0-1-42",
  "region": "us-east-1",
  "tags": {"env": "production", "team": "platform"}
}
```

**Event types:** `cpu_usage`, `memory_usage`, `disk_io`, `network_latency`, `network_throughput`, `process_count`, `uptime`, `health_check`, `custom`

**Severities:** `info`, `warning`, `critical`

## 📄 Licença

Copyright 2026 Davi Laurindo

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
