# Migration: Docker Compose → k3s + GitOps

## Datum
15. April 2026

## Ausgangslage
- OVH VPS mit Docker Compose Stack (`ai-lab/docker-compose.yml`)
- 10+ Services als Docker Container
- Traefik v2 als Reverse Proxy
- Manuelle Deployments via `docker compose up`
- Keine zentrale Observability
- Secrets im `.env` File auf dem Server

## Ziel
- Kubernetes (k3s) mit GitOps (ArgoCD)
- Automatisches Deployment via `git push`
- Secrets verschluesselt in Git (Sealed Secrets)
- Vollstaendiges Monitoring + Logging
- TLS-Automatisierung via cert-manager

## Migrationsschritte (13-Step Big Bang)

### Schritt 1: Discovery
- Alle Docker Compose Services analysiert
- Ports, Volumes, Environment Variables dokumentiert
- Abhaengigkeiten zwischen Services identifiziert

### Schritt 2: k3s Installation
```bash
curl -sfL https://get.k3s.io | sh -
```
- k3s v1.34.6 auf Ubuntu 25.04
- Traefik v3 als built-in Ingress Controller
- local-path als default StorageClass

### Schritt 3: ArgoCD Setup
- ArgoCD v2.14.12 im `infra` Namespace installiert
- App-of-Apps Pattern: Eine Root Application verwaltet alle anderen
- AppProject `ai-lab` mit Source/Destination Restrictions
- IngressRoute fuer ArgoCD Web UI

### Schritt 4: cert-manager
- cert-manager v1.17.2 via Helm
- ClusterIssuer `letsencrypt-prod` (HTTP-01 Challenge)
- Jede IngressRoute hat ein zugehoeriges Certificate-Objekt

### Schritt 5: Sealed Secrets
- Bitnami Sealed Secrets Controller installiert
- Alle Secrets mit `kubeseal` verschluesselt
- Sealed Secrets liegen im Git, Controller entschluesselt sie im Cluster

### Schritt 6: Basis-Services
- Portal (GHCR Image)
- Portfolio (Hugo + Toha, GHCR Image)
- Ollama (20Gi PVC fuer Modelle)
- Qdrant (Dual PVCs: Storage + Snapshots)

### Schritt 7: Authentik SSO
- Postgres + Redis als Dependencies
- Server + Worker Deployment
- **Wichtig:** `args: [server]` statt `command: [ak, server]` — sonst werden DB-Migrationen uebersprungen
- **Wichtig:** Kein Redis mehr noetig seit Authentik 2026.x
- **Wichtig:** Volume Mount auf `/data` statt `/media`

### Schritt 8: AI Services
- LiteLLM Proxy (Routing zu Ollama + externe APIs)
- Open WebUI (Chat Interface, OIDC-Auth via Authentik)
- Langfuse v2 (LLM Tracing, braucht kein ClickHouse)
- MLflow (Experiment Tracking, `pip install psycopg2-binary` im Startup)
- SDLC Pilot Backend + Frontend (GHCR Images, nginx ConfigMap fuer API-Proxy)

### Schritt 9: Monitoring
- kube-prometheus-stack via Helm (Prometheus + Grafana + AlertManager)
- k3s-Optimierungen: etcd/scheduler/proxy Exporter deaktiviert
- 15 Tage Retention, 10Gi Storage
- IngressRoutes fuer Grafana + Prometheus

### Schritt 10: Logging
- Loki SingleBinary Mode (10Gi, filesystem Storage)
- Promtail als DaemonSet (sammelt Logs von allen Pods)
- Grafana Datasource automatisch konfiguriert

### Schritt 11: CI/CD
- GitHub Actions Workflow fuer SDLC Pilot
- Build: Backend + Frontend Docker Images
- Push: GHCR mit `:latest` und `:sha` Tags
- Deploy: `kubectl rollout restart` nach Image-Update

### Schritt 12: Smoke Tests
- Alle 13 TLS-Zertifikate valid
- Alle Pods Running
- Alle ArgoCD Applications Synced + Healthy
- Alle Endpoints erreichbar

### Schritt 13: Dokumentation
- README.md, ARCHITECTURE.md, MIGRATION.md, RUNBOOK.md
- GITOPS-WORKFLOW.md, MONITORING.md, LENS-GUIDE.md
- LEARN.md, DISASTER-RECOVERY.md

## Probleme und Loesungen

| Problem | Ursache | Loesung |
|---------|---------|---------|
| Authentik `group_id` FieldError | `command: [ak, server]` ueberschreibt ENTRYPOINT → Migrationen laufen nicht | `args: [server]` verwenden |
| Langfuse v3 braucht ClickHouse | v3 hat ClickHouse als Pflicht-Dependency | Langfuse v2 verwenden |
| MLflow `--allowed-hosts` unbekannt | Flag existiert nicht in aktueller Version | Flag entfernen |
| MLflow `psycopg2` fehlt | Base Image hat keinen Postgres-Driver | `pip install psycopg2-binary` im Startup |
| SDLC Frontend `upstream "backend" not found` | Docker Compose Hostname ≠ k8s Service Name | nginx ConfigMap mit `sdlc-pilot-backend:8001` |
| GHCR ImagePullBackOff | Private Packages brauchen Pull-Credentials | `ghcr-credentials` Secret erstellt |
| Portal zeigt leere Seite | ConfigMap hatte Platzhalter-HTML | Docker Image auf GHCR gebaut |

## Geloeschte Repos (Cleanup)
- `ai-lab` — alter Docker Compose Stack
- `vps-infra` — altes Docker/Traefik Setup
- `aicodegencrew-old` — alte Version von SDLC Pilot
- `portfolio` (alt) — Hugo-Site, neu erstellt mit Toha Theme
- Diverse Forks (thingsboard, Archon, claude-code-best-practice)

## Ergebnis
- 37 Pods laufen (apps + monitoring + infra + cert-manager)
- 13 TLS-Zertifikate aktiv
- 10 ArgoCD Applications synced
- 14 PVCs (~56Gi)
- 12 HTTPS-Endpoints
