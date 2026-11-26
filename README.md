# OpsPilot

[![CI](https://github.com/mehaktewari/opspilot/actions/workflows/ci.yml/badge.svg)](https://github.com/mehaktewari/opspilot/actions/workflows/ci.yml)
[![Security](https://github.com/mehaktewari/opspilot/actions/workflows/security.yml/badge.svg)](https://github.com/mehaktewari/opspilot/actions/workflows/security.yml)

An AI DevOps teammate: it watches a running system, explains incidents in plain English, and proposes fixes (rollback, scale, restart) that a human approves before anything changes.

> Status: **Day 7** — laptop-friendly local mode: the whole stack runs on an 8 GB machine.

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

Needs Docker Desktop, [kind](https://kind.sigs.k8s.io/), kubectl and [Helm](https://helm.sh/).

```bash
bash scripts/cluster-up.sh     # create cluster, build + load images, helm install, smoke test
# inventory: http://127.0.0.1:9001/docs   orders: http://127.0.0.1:9002/docs
bash scripts/cluster-down.sh   # delete the cluster
```

The app is packaged as a Helm chart in `deploy/helm/opspilot-app/`. Each service runs with
readiness/liveness probes, CPU/memory limits, zero-downtime rolling updates, a PodDisruptionBudget,
and a locked-down security context (non-root, read-only filesystem, no privilege escalation, all
capabilities dropped). The namespace enforces the Kubernetes **restricted** Pod Security Standard,
so a pod that breaks these rules is rejected. Scripts always use the `kind-opspilot` kubectl
context so they can never touch another cluster.

| Environment | Values file | Replicas | Service | Images |
|---|---|---|---|---|
| dev (kind) | `values.yaml` | 1 | NodePort | local `opspilot/<svc>:dev` |
| staging | `values-staging.yaml` | 1 | ClusterIP | `ghcr.io/mehaktewari/opspilot-<svc>:main` |
| prod | `values-prod.yaml` | 3 (PDB min 2) | ClusterIP | `ghcr.io/mehaktewari/opspilot-<svc>:1.0.0` |

Preview what an environment would deploy:

```bash
helm template opspilot deploy/helm/opspilot-app -f deploy/helm/opspilot-app/values-prod.yaml
```

## Running on a small laptop

The local setup is tuned to fit on an 8 GB machine next to a browser and an IDE:

- **1 replica per service** in dev (`values.yaml`). Staging and prod keep their own replica counts.
- **Preflight check**: `cluster-up.sh` first runs `scripts/preflight.sh`, which shows free RAM and disk,
  lists the biggest memory users, and refuses to start under 1.5 GB free (override with `FORCE=1`).
- **Slim Argo CD**: `argocd-up.sh` turns off the parts not needed locally (Dex SSO, notifications,
  ApplicationSets: 7 pods down to 4) and sets CPU/memory limits, since upstream ships with none.
- **startupProbe** on every service, so a slow boot on a busy machine isn't killed by the liveness probe.

## GitOps with Argo CD

After `cluster-up.sh`, hand the app over to Argo CD:

```bash
bash scripts/argocd-up.sh
kubectl --context kind-opspilot -n argocd port-forward svc/argocd-server 8080:443
# https://localhost:8080  (user admin, password printed by the script)
```

`deploy/argocd/opspilot-dev.yaml` tells Argo CD to keep the `opspilot` namespace identical to
`deploy/helm/opspilot-app` on `main`:

- **Git is the source of truth.** Change `values.yaml`, push, and Argo CD rolls it out (no `helm` or `kubectl` needed).
- **Self-heal.** A manual `kubectl scale` or `kubectl edit` is reverted to what Git says.
- **Prune.** Resources removed from the chart are deleted from the cluster.
- **Rollback = `git revert`.** Every deploy is a commit, so history, review and undo come for free.
  OpsPilot's AI agent will use exactly this path to roll back a bad release.

## Run tests

```bash
cd services/inventory && pip install -r requirements.txt -r requirements-dev.txt && pytest -q
cd ../orders && pip install -r requirements.txt -r requirements-dev.txt && pytest -q
```

## CI

Every push and pull request runs `.github/workflows/ci.yml`:

1. **test**: pytest for each service on Python 3.12 and 3.14 (4 jobs in parallel)
2. **docker-build**: builds each image and checks `/healthz` responds
3. **k8s-validate**: `helm lint --strict`, then renders the chart for dev, staging and prod and validates each against Kubernetes 1.37 schemas (kubeconform)
4. **e2e-kind**: creates a real kind cluster, installs the chart with Helm and runs a smoke test

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
- [x] Helm chart with dev / staging / prod values
- [x] Argo CD (GitOps) with auto-sync and self-heal for dev
- [x] Laptop-friendly local mode (8 GB): preflight check, slim Argo CD, 1 replica in dev
- [ ] Publish images to GHCR + promote to staging/prod
- [ ] Prometheus, Grafana, Loki, alerts
- [ ] AI agent (read-only tools, root-cause summaries)
- [ ] Dashboard + approval flow
- [ ] Guarded write actions (rollback/scale) with OPA
- [ ] RAG over runbooks, AI red-team tests in CI
