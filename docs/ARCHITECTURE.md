# Architektur — AI Lab Platform

## Ueberblick

Die AI Lab Platform ist ein Self-Hosted Sovereign AI Stack. Alle Komponenten laufen auf einem einzelnen OVH VPS (4 vCPU, 8GB RAM, 80GB SSD) unter k3s Kubernetes.

**Design-Prinzipien:**
- GitOps-First: Jede Aenderung geht durch Git → ArgoCD synct automatisch
- Secrets nie im Klartext in Git (Sealed Secrets)
- Jeder Service hat Resource Limits
- Einheitliche Labels fuer Filterung (app.kubernetes.io/*)
- TLS ueberall via cert-manager + Let's Encrypt

## Architektur-Diagramm

```
                    ┌─────────────────────────────────────┐
                    │            Internet                   │
                    └──────────────┬──────────────────────┘
                                   │
                    ┌──────────────▼──────────────────────┐
                    │     Traefik Ingress Controller        │
                    │     (k3s built-in, Port 443/80)       │
                    │     TLS Termination via cert-manager   │
                    └──────────────┬──────────────────────┘
                                   │
          ┌────────────────────────┼────────────────────────┐
          │                        │                        │
   ┌──────▼──────┐    ┌───────────▼──────────┐   ┌────────▼────────┐
   │ Namespace:   │    │ Namespace: apps       │   │ Namespace:      │
   │ infra        │    │                       │   │ monitoring      │
   │              │    │  ┌───────────────┐    │   │                 │
   │ ArgoCD       │    │  │ Authentik SSO │    │   │ Prometheus      │
   │ Sealed Sec.  │    │  └───────┬───────┘    │   │ Grafana         │
   └──────────────┘    │          │ OIDC       │   │ AlertManager    │
                       │  ┌───────▼───────┐    │   │ Loki            │
                       │  │ Open WebUI    │    │   │ Promtail        │
                       │  │ Langfuse      │    │   └─────────────────┘
                       │  └───────────────┘    │
                       │                       │
                       │  ┌───────────────┐    │
                       │  │ Ollama (LLM)  │◄───┤
                       │  └───────┬───────┘    │
                       │          │            │
                       │  ┌───────▼───────┐    │
                       │  │ LiteLLM Proxy │    │
                       │  └───────┬───────┘    │
                       │          │            │
                       │  ┌───────▼───────┐    │
                       │  │ SDLC Pilot    │    │
                       │  │ (BE + FE)     │    │
                       │  └───────┬───────┘    │
                       │          │            │
                       │  ┌───────▼───────┐    │
                       │  │ Qdrant        │    │
                       │  │ (Vector DB)   │    │
                       │  └───────────────┘    │
                       │                       │
                       │  ┌───────────────┐    │
                       │  │ MLflow        │    │
                       │  │ Langfuse      │    │
                       │  │ (Observ.)     │    │
                       │  └───────────────┘    │
                       │                       │
                       │  ┌───────────────┐    │
                       │  │ Portal        │    │
                       │  │ Portfolio     │    │
                       │  └───────────────┘    │
                       └───────────────────────┘
```

## Namespaces

| Namespace | Zweck | Services |
|-----------|-------|----------|
| `infra` | Cluster-Infrastruktur | ArgoCD, Sealed Secrets Controller |
| `apps` | Anwendungen | 10 Services (Portal, Authentik, Ollama, etc.) |
| `monitoring` | Observability | Prometheus, Grafana, AlertManager, Loki, Promtail |
| `cert-manager` | TLS Automation | cert-manager Controller + Webhooks |
| `kube-system` | k3s System | Traefik, CoreDNS, local-path-provisioner |

## Datenfluss

### LLM-Pipeline
```
User → Open WebUI → LiteLLM Proxy → Ollama (lokal)
                                   → OpenAI API (extern, optional)
```

### SDLC Pilot
```
User → Frontend (Angular/nginx) → Backend (FastAPI)
                                     ├── LiteLLM (LLM Aufrufe)
                                     ├── Qdrant (Vector Search / RAG)
                                     ├── MLflow (Experiment Tracking)
                                     └── Langfuse (LLM Tracing)
```

### Auth-Flow
```
User → Traefik → Forward Auth Middleware → Authentik
                                             │ OIDC Token
                                             ▼
                                         Backend Service
```

## Storage

Alle PVCs nutzen `local-path` (k3s default StorageClass). Daten liegen unter `/var/lib/rancher/k3s/storage/` auf dem VPS.

| PVC | Groesse | Service | Inhalt |
|-----|---------|---------|--------|
| ollama-models | 20Gi | Ollama | LLM Modelle (qwen2.5:3b etc.) |
| open-webui-data | 5Gi | Open WebUI | Chat History, User Data |
| qdrant-storage | 5Gi | Qdrant | Vector Collections |
| qdrant-snapshots | 2Gi | Qdrant | Backups |
| sdlc-pilot-repo-cache | 5Gi | SDLC Pilot | Geklonte Repos |
| sdlc-pilot-knowledge | 2Gi | SDLC Pilot | Knowledge Base |
| sdlc-pilot-fastembed-cache | 2Gi | SDLC Pilot | Embedding Model Cache |
| mlflow-artifacts | 5Gi | MLflow | Experiment Artifacts |
| mlflow-postgres-data | 2Gi | MLflow | PostgreSQL Daten |
| langfuse-postgres-data | 2Gi | Langfuse | PostgreSQL Daten |
| authentik-data | 1Gi | Authentik | Media + Custom Templates |
| authentik-postgres-data | 2Gi | Authentik | PostgreSQL Daten |
| authentik-redis-data | 1Gi | Authentik | Redis Cache |

**Gesamt: ~56Gi belegt auf 80Gi SSD**

## Netzwerk

- **Ingress:** Traefik v3 (k3s built-in) mit IngressRoute CRDs
- **TLS:** cert-manager mit Let's Encrypt (ClusterIssuer: `letsencrypt-prod`)
- **DNS:** Alle `*.aymenmastouri.io` Domains zeigen auf 51.195.116.255
- **Service Discovery:** Kubernetes DNS (z.B. `ollama:11434`, `litellm:4000`)
- **Externe Ports:** Nur 80 (→ 443 Redirect) und 443 (TLS)

## ArgoCD App-of-Apps

```
app-of-apps (Root)
├── portal          (Wave 0)
├── portfolio       (Wave 0)
├── authentik       (Wave 1)
├── ollama          (Wave 2)
├── qdrant          (Wave 2)
├── litellm         (Wave 3)
├── langfuse        (Wave 3)
├── mlflow          (Wave 3)
├── open-webui      (Wave 4)
└── sdlc-pilot      (Wave 5)
```

Jede Application ueberwacht einen Ordner unter `apps/<name>/` und synct automatisch bei Aenderungen (auto-sync + self-heal + prune).
