# k8s-manifests

GitOps-Kubernetes-Manifests fuer die **AI Lab** Plattform auf einem OVH VPS.

Alles wird ueber ArgoCD (App-of-Apps) deployed. Ein `git push` auf `main` triggert automatisch das Deployment.

## Architektur

```
OVH VPS (51.195.116.255) — k3s v1.34.6 — Ubuntu 25.04
│
├── Namespace: infra
│   ├── ArgoCD v2.14.12         (GitOps Controller)
│   └── Sealed Secrets          (Git-safe verschluesselte Secrets)
│
├── Namespace: apps
│   ├── Portal                  → ai.aymenmastouri.io        (Landing Page)
│   ├── Portfolio               → aymenmastouri.io            (Hugo + Toha)
│   ├── Authentik SSO           → auth.aymenmastouri.io       (OIDC/SAML)
│   ├── Ollama                  → intern                      (LLM Runtime)
│   ├── Qdrant                  → qdrant.aymenmastouri.io     (Vector DB)
│   ├── LiteLLM                 → llm.aymenmastouri.io        (LLM Proxy)
│   ├── Open WebUI              → chat.aymenmastouri.io       (Chat UI)
│   ├── Langfuse                → langfuse.aymenmastouri.io   (LLM Traces)
│   ├── MLflow                  → mlflow.aymenmastouri.io     (Experiments)
│   └── SDLC Pilot (BE+FE)     → sdlc.aymenmastouri.io       (AI SDLC Tool)
│
├── Namespace: monitoring
│   ├── Prometheus              → prometheus.aymenmastouri.io
│   ├── Grafana                 → grafana.aymenmastouri.io
│   ├── AlertManager
│   ├── Loki                    (Log Aggregation)
│   └── Promtail               (Log Shipper)
│
└── Namespace: cert-manager
    └── cert-manager v1.17.2    (Let's Encrypt TLS)
```

## Repository-Struktur

```
k8s-manifests/
├── apps/                          # Ein Ordner pro Service
│   ├── authentik/                 # SSO: Postgres, Redis, Server, Worker
│   ├── langfuse/                  # LLM Observability: Postgres, Deployment
│   ├── litellm/                   # LLM Proxy: Deployment, ConfigMap
│   ├── mlflow/                    # Experiment Tracking: Postgres, Deployment
│   ├── ollama/                    # LLM Runtime: Deployment (20Gi PVC)
│   ├── open-webui/                # Chat UI: Deployment
│   ├── portal/                    # Landing Page: GHCR Image
│   ├── portfolio/                 # Portfolio: Hugo/Toha GHCR Image
│   ├── qdrant/                    # Vector DB: Deployment (dual PVCs)
│   └── sdlc-pilot/               # SDLC Tool: Backend + Frontend + ConfigMap
├── argocd/
│   ├── app-of-apps.yaml           # Root Application
│   ├── projects/ai-lab.yaml       # AppProject
│   └── applications/              # 10 ArgoCD Applications
├── infrastructure/
│   ├── cert-manager/              # TLS Automation
│   ├── monitoring/                # kube-prometheus-stack Values + IngressRoutes
│   ├── logging/                   # Loki + Promtail Values
│   └── sealed-secrets/            # Bitnami Sealed Secrets
└── docs/                          # Dokumentation
    ├── ARCHITECTURE.md
    ├── MIGRATION.md
    ├── RUNBOOK.md
    ├── GITOPS-WORKFLOW.md
    ├── MONITORING.md
    ├── LENS-GUIDE.md
    ├── LEARN.md
    └── DISASTER-RECOVERY.md
```

## Stack

| Komponente | Version | Zweck |
|-----------|---------|-------|
| k3s | v1.34.6 | Leichtgewichtiges Kubernetes |
| ArgoCD | v2.14.12 | GitOps Continuous Delivery |
| Traefik | v3 (k3s built-in) | Ingress + TLS Termination |
| cert-manager | v1.17.2 | Let's Encrypt Zertifikate |
| Sealed Secrets | Bitnami | Git-sichere verschluesselte Secrets |
| Prometheus | kube-prometheus-stack | Metrics + Alerting |
| Grafana | latest | Dashboards (3 Datasources) |
| Loki | v3.6.7 | Log Aggregation |
| Promtail | v3.5.1 | Log Shipping |

## Sync-Waves (Deployment-Reihenfolge)

| Wave | Services |
|------|----------|
| 0 | Portal, Portfolio |
| 1 | Authentik (SSO Provider) |
| 2 | Ollama, Qdrant |
| 3 | LiteLLM, Langfuse, MLflow |
| 4 | Open WebUI |
| 5 | SDLC Pilot |

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
| https://mlflow.aymenmastouri.io | MLflow | Forward Auth |
| https://sdlc.aymenmastouri.io | SDLC Pilot | Public |
| https://grafana.aymenmastouri.io | Grafana | admin/admin |
| https://prometheus.aymenmastouri.io | Prometheus | Public |

## Quick Commands

```bash
# Alle Pods pruefen
kubectl get pods -n apps
kubectl get pods -n monitoring

# ArgoCD Status
kubectl get applications -n infra

# Force Sync
kubectl -n infra annotate application <name> argocd.argoproj.io/refresh=hard --overwrite

# TLS Zertifikate
kubectl get certificates -A

# Logs eines Services
kubectl logs -n apps deploy/<name> --tail=50

# Rollout nach Image-Update
kubectl rollout restart deployment <name> -n apps

# Ollama Modelle
kubectl exec -n apps deploy/ollama -- ollama pull qwen2.5:3b
kubectl exec -n apps deploy/ollama -- ollama list
```

## Dokumentation

| Dokument | Inhalt |
|----------|--------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Gesamt-Architektur mit Diagramm |
| [MIGRATION.md](docs/MIGRATION.md) | Was wurde bei der Migration gemacht |
| [RUNBOOK.md](docs/RUNBOOK.md) | Operations: Restart, Logs, Backup, Restore |
| [GITOPS-WORKFLOW.md](docs/GITOPS-WORKFLOW.md) | Wie deploye ich Aenderungen |
| [MONITORING.md](docs/MONITORING.md) | Grafana, Prometheus, Loki nutzen |
| [LENS-GUIDE.md](docs/LENS-GUIDE.md) | Lens fuer Cluster-Management |
| [LEARN.md](docs/LEARN.md) | Lern-Notes pro Komponente |
| [DISASTER-RECOVERY.md](docs/DISASTER-RECOVERY.md) | Was tun wenn alles brennt |
