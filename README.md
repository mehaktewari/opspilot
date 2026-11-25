# OpsPilot

An AI DevOps teammate: it watches a running system, explains incidents in plain English, and proposes fixes (rollback, scale, restart) that a human approves before anything changes.

> Status: **Day 1** — sample microservices running locally with Docker Compose.

## Sample app

A small pharmacy backend that OpsPilot monitors (and that we break on purpose):

| Service | Port | What it does |
|---|---|---|
| `inventory` | 8001 | Medicines, stock levels, low-stock check, stock reservation |
| `orders` | 8002 | Places orders by reserving stock in `inventory` |

Both expose `/healthz` and Prometheus metrics at `/metrics`.

## Run locally

```bash
docker compose up --build
curl localhost:8001/low-stock
curl -X POST localhost:8002/orders -H "Content-Type: application/json" -d '{"sku":"paracetamol-500","qty":2}'
```

Simulate a bad release (slow responses + random 500s):

```bash
BUGGY=true docker compose up --build inventory
```

## Run tests

```bash
cd services/inventory && pip install -r requirements.txt -r requirements-dev.txt && pytest -q
cd ../orders && pip install -r requirements.txt -r requirements-dev.txt && pytest -q
```

## Roadmap

- [x] Sample services + Docker Compose
- [ ] CI: tests, Trivy, Gitleaks
- [ ] Kubernetes + Helm + Argo CD
- [ ] Prometheus, Grafana, Loki, alerts
- [ ] AI agent (read-only tools, root-cause summaries)
- [ ] Dashboard + approval flow
- [ ] Guarded write actions (rollback/scale) with OPA
- [ ] RAG over runbooks, AI red-team tests in CI
