# OpsPilot

[![CI](https://github.com/mehaktewari/opspilot/actions/workflows/ci.yml/badge.svg)](https://github.com/mehaktewari/opspilot/actions/workflows/ci.yml)
[![Security](https://github.com/mehaktewari/opspilot/actions/workflows/security.yml/badge.svg)](https://github.com/mehaktewari/opspilot/actions/workflows/security.yml)

An AI DevOps teammate: it watches a running system, explains incidents in plain English, and proposes fixes (rollback, scale, restart) that a human approves before anything changes.

> Status: **Day 4** — running on Kubernetes (kind) with hardened manifests and an e2e test in CI.

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

## Run on Kubernetes (kind)

Needs Docker Desktop, [kind](https://kind.sigs.k8s.io/) and kubectl.

```bash
bash scripts/cluster-up.sh     # create cluster, build + load images, deploy, smoke test
# inventory: http://127.0.0.1:9001/docs   orders: http://127.0.0.1:9002/docs
bash scripts/cluster-down.sh   # delete the cluster
```

Manifests live in `deploy/k8s/`. Each service runs 2 replicas with readiness/liveness probes,
CPU/memory limits, zero-downtime rolling updates, and a locked-down security context
(non-root, read-only filesystem, no privilege escalation, all capabilities dropped).
The namespace enforces the Kubernetes **restricted** Pod Security Standard, so a pod that
breaks these rules is rejected. Scripts always use the `kind-opspilot` kubectl context so they
can never touch another cluster.

## Run tests

```bash
cd services/inventory && pip install -r requirements.txt -r requirements-dev.txt && pytest -q
cd ../orders && pip install -r requirements.txt -r requirements-dev.txt && pytest -q
```

## CI

Every push and pull request runs `.github/workflows/ci.yml`:

1. **test**: pytest for each service on Python 3.12 and 3.14 (4 jobs in parallel)
2. **docker-build**: builds each image and checks `/healthz` responds
3. **k8s-validate**: checks manifests against Kubernetes 1.37 schemas (kubeconform)
4. **e2e-kind**: creates a real kind cluster, deploys both services and runs a smoke test

## Security

`.github/workflows/security.yml` runs on every push, every PR, and weekly:

| Check | Tool | Fails the build on |
|---|---|---|
| Secrets in git history | Gitleaks | any leak |
| Python deps, Dockerfiles, secrets in files | Trivy (fs) | HIGH / CRITICAL with a fix available |
| Built container images | Trivy (image) | CRITICAL with a fix available |

Findings are uploaded as SARIF to the repo's **Security → Code scanning** tab. Dependabot opens weekly PRs for Python packages, base images and GitHub Actions, and all actions are pinned to commit SHAs.

## Roadmap

- [x] Sample services + Docker Compose
- [x] CI: tests + Docker build/smoke test
- [x] Security scans: Gitleaks, Trivy, Dependabot, SHA-pinned actions
- [x] Kubernetes (kind) with restricted pod security + e2e in CI
- [ ] Helm + Argo CD (GitOps)
- [ ] Prometheus, Grafana, Loki, alerts
- [ ] AI agent (read-only tools, root-cause summaries)
- [ ] Dashboard + approval flow
- [ ] Guarded write actions (rollback/scale) with OPA
- [ ] RAG over runbooks, AI red-team tests in CI
