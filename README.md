# k8s-manifests

Kubernetes manifests for the **AI Lab** platform. Fully managed by ArgoCD (GitOps).

## Architecture

```
OVH VPS (51.195.116.255) — k3s v1.34.6
├── Namespace: infra
│   └── ArgoCD v2.14.12 (App-of-Apps pattern)
├── Namespace: apps
│   ├── Portal             → ai.aymenmastouri.io
│   ├── Portfolio           → aymenmastouri.io
│   ├── Authentik SSO       → auth.aymenmastouri.io
│   ├── Ollama (LLM)       → internal
│   ├── Qdrant (VectorDB)  → qdrant.aymenmastouri.io
│   ├── LiteLLM (Proxy)    → llm.aymenmastouri.io
│   ├── Open WebUI (Chat)  → chat.aymenmastouri.io
│   ├── Langfuse (Traces)  → langfuse.aymenmastouri.io
│   ├── MLflow (Experiments)→ mlflow.aymenmastouri.io
│   └── SDLC Pilot (BE+FE) → sdlc.aymenmastouri.io / sdlc-api.aymenmastouri.io
└── Namespace: monitoring
    ├── Prometheus          → prometheus.aymenmastouri.io
    ├── Grafana             → grafana.aymenmastouri.io
    ├── AlertManager
    ├── Loki (Logs)
    └── Promtail (Log Shipper)
```

## Repository Structure

```
k8s-manifests/
├── apps/
│   ├── authentik/          # SSO: Postgres, Redis, Server, Worker, IngressRoute
│   ├── langfuse/           # LLM Observability: Postgres, Deployment, IngressRoute
│   ├── litellm/            # LLM Proxy: Deployment, ConfigMap, IngressRoute
│   ├── mlflow/             # Experiment Tracking: Postgres, Deployment, IngressRoute
│   ├── ollama/             # Local LLM Runtime: Deployment (20Gi PVC)
│   ├── open-webui/         # Chat UI: Deployment, IngressRoute
│   ├── portal/             # Landing Page: Deployment (GHCR image)
│   ├── portfolio/          # Personal Site: Deployment, ConfigMap
│   ├── qdrant/             # Vector DB: Deployment (dual PVCs)
│   └── sdlc-pilot/         # SDLC Tool: Backend + Frontend Deployments, ConfigMap
├── argocd/
│   ├── app-of-apps.yaml    # Root Application (watches applications/)
│   ├── projects/
│   │   └── ai-lab.yaml     # AppProject definition
│   └── applications/       # One Application per service (10 total)
└── infrastructure/
    ├── cert-manager/        # TLS automation (Let's Encrypt)
    ├── monitoring/          # kube-prometheus-stack values + IngressRoutes
    ├── logging/             # Loki + Promtail values
    └── sealed-secrets/      # Bitnami Sealed Secrets
```

## Stack

| Component | Version | Purpose |
|-----------|---------|---------|
| k3s | v1.34.6 | Lightweight Kubernetes |
| ArgoCD | v2.14.12 | GitOps continuous delivery |
| Traefik | v3 (k3s built-in) | Ingress + TLS termination |
| cert-manager | v1.17.2 | Automated Let's Encrypt certificates |
| Sealed Secrets | Bitnami | Git-safe encrypted secrets |
| Prometheus | v0.90.1 | Metrics collection (13 targets) |
| Grafana | latest | Dashboards (3 datasources) |
| AlertManager | latest | Alert routing |
| Loki | v3.6.7 | Log aggregation |
| Promtail | v3.5.1 | Log shipping |

## GitOps Workflow

```
1. Edit manifests → git push to main
2. ArgoCD detects changes (3 min poll or manual refresh)
3. ArgoCD syncs to cluster (auto-prune + self-heal)
```

### Sync Waves (Deployment Order)

| Wave | Services |
|------|----------|
| 0 | Portal |
| 1 | Authentik (SSO provider) |
| 2 | Ollama, Qdrant, Portfolio |
| 3 | LiteLLM, Langfuse, MLflow |
| 4 | Open WebUI |
| 5 | SDLC Pilot |

## CI/CD

SDLC Pilot images are built via GitHub Actions on push to `main`:
- `ghcr.io/aymenmastouri/aicodegencrew-backend:latest`
- `ghcr.io/aymenmastouri/aicodegencrew-frontend:latest`

Portal image: `ghcr.io/aymenmastouri/ai-lab-portal:latest`

To redeploy after image update:
```bash
kubectl rollout restart deployment <name> -n apps
```

## Secrets Management

Secrets are encrypted with Sealed Secrets (public key encryption).
Only the cluster controller can decrypt them.

```bash
# Seal a new secret
kubeseal --format yaml < secret.yaml > sealed-secret.yaml

# GHCR pull credentials (created manually, not in Git)
kubectl get secret ghcr-credentials -n apps
```

## Quick Commands

```bash
# Check all services
kubectl get pods -n apps
kubectl get pods -n monitoring

# ArgoCD status
kubectl get applications -n infra

# Force sync
kubectl -n infra annotate application <name> argocd.argoproj.io/refresh=hard --overwrite

# TLS certificates
kubectl get certificates -A

# Logs (via Loki in Grafana or kubectl)
kubectl logs -n apps deploy/<name> --tail=50

# Pull Ollama models
kubectl exec -n apps deploy/ollama -- ollama pull qwen2.5:3b
```

## Endpoints

| URL | Service | Auth |
|-----|---------|------|
| https://ai.aymenmastouri.io | Portal | Public |
| https://aymenmastouri.io | Portfolio | Public |
| https://auth.aymenmastouri.io | Authentik SSO | Public |
| https://chat.aymenmastouri.io | Open WebUI | OIDC (Authentik) |
| https://llm.aymenmastouri.io | LiteLLM | API Key |
| https://qdrant.aymenmastouri.io | Qdrant | API Key |
| https://langfuse.aymenmastouri.io | Langfuse | OIDC (Authentik) |
| https://mlflow.aymenmastouri.io | MLflow | Public |
| https://sdlc.aymenmastouri.io | SDLC Pilot | Public |
| https://sdlc-api.aymenmastouri.io | SDLC Pilot API | Public |
| https://grafana.aymenmastouri.io | Grafana | admin/admin |
| https://prometheus.aymenmastouri.io | Prometheus | Public |
