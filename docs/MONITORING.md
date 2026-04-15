# Monitoring & Logging Guide

## Ueberblick

```
Prometheus ──→ sammelt Metriken von allen Pods (Pull-Modell, alle 30s)
Grafana    ──→ visualisiert Metriken + Logs (3 Datasources)
AlertManager → benachrichtigt bei Problemen
Loki       ──→ aggregiert alle Container-Logs
Promtail   ──→ schickt Logs von jedem Node an Loki
```

## Zugang

| Tool | URL | Credentials |
|------|-----|------------|
| Grafana | https://grafana.aymenmastouri.io | admin / admin |
| Prometheus | https://prometheus.aymenmastouri.io | kein Login |

## Grafana

### Datasources (vorkonfiguriert)
1. **Prometheus** — Metriken (CPU, RAM, Network, etc.)
2. **Loki** — Logs (alle Container-Logs)
3. **AlertManager** — Alert-Status

### Wichtige Dashboards

Nach dem Login → Dashboards → Browse:

- **Kubernetes / Compute Resources / Namespace (Pods)** — CPU/RAM pro Pod
- **Kubernetes / Compute Resources / Node** — Node-Auslastung
- **Kubernetes / Networking / Namespace** — Netzwerk-Traffic
- **Node Exporter Full** — Disk, RAM, CPU des VPS

### Eigenes Dashboard erstellen
1. Dashboards → New → New Dashboard
2. Add visualization → Prometheus Datasource
3. Beispiel-Queries:

```promql
# CPU-Nutzung pro Pod (Namespace apps)
sum(rate(container_cpu_usage_seconds_total{namespace="apps"}[5m])) by (pod)

# RAM-Nutzung pro Pod
sum(container_memory_working_set_bytes{namespace="apps"}) by (pod) / 1024 / 1024

# Pod Restart Count
kube_pod_container_status_restarts_total{namespace="apps"}

# Disk-Nutzung der PVCs
kubelet_volume_stats_used_bytes{namespace="apps"} / kubelet_volume_stats_capacity_bytes{namespace="apps"} * 100
```

## Prometheus

### Direkt Queries ausfuehren
1. Oeffne https://prometheus.aymenmastouri.io
2. Expression-Box → Query eingeben → Execute

### Nuetzliche PromQL-Queries

```promql
# Welche Pods laufen?
kube_pod_info{namespace="apps"}

# Pods die nicht Ready sind
kube_pod_status_ready{namespace="apps", condition="false"}

# Container Restarts (letzte Stunde)
increase(kube_pod_container_status_restarts_total{namespace="apps"}[1h])

# Node CPU-Auslastung (%)
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Node RAM-Auslastung (%)
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# Disk-Auslastung (%)
(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100

# HTTP-Anfragen an Traefik
rate(traefik_entrypoint_requests_total[5m])
```

### Targets pruefen
Prometheus → Status → Targets → zeigt alle Scrape-Targets und deren Status.

## Loki (Logs)

### Logs in Grafana anschauen
1. Grafana → Explore (Kompass-Icon links)
2. Datasource: **Loki** auswaehlen
3. Label Browser oder LogQL verwenden

### LogQL-Queries

```logql
# Alle Logs aus Namespace apps
{namespace="apps"}

# Logs eines bestimmten Service
{namespace="apps", pod=~"ollama.*"}

# Nur Error-Logs
{namespace="apps"} |= "error"

# Authentik Server Logs
{namespace="apps", pod=~"authentik-server.*"}

# SDLC Pilot Backend Logs
{namespace="apps", pod=~"sdlc-pilot-backend.*"}

# Logs mit JSON-Parsing
{namespace="apps", pod=~"authentik-server.*"} | json | level="error"

# Log-Rate pro Service (Logs/Sekunde)
sum(rate({namespace="apps"}[5m])) by (pod)
```

### Logs via kubectl (schnell)
```bash
# Live-Logs
kubectl logs -n apps deploy/ollama -f --tail=50

# Logs der letzten 10 Minuten
kubectl logs -n apps deploy/ollama --since=10m

# Logs des vorherigen Containers (nach Crash)
kubectl logs -n apps <pod-name> --previous
```

## AlertManager

### Aktive Alerts pruefen
```bash
# Via kubectl
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093
# Dann: http://localhost:9093

# Via Grafana
Grafana → Alerting → Alert Rules
```

### Wichtige Default-Alerts (kube-prometheus-stack)
- **KubePodCrashLooping** — Pod startet immer wieder neu
- **KubePodNotReady** — Pod ist nicht ready
- **KubeDeploymentReplicasMismatch** — Gewuenschte ≠ aktuelle Replicas
- **NodeFilesystemSpaceFillingUp** — Disk wird voll
- **NodeMemoryHighUtilization** — RAM wird knapp

## Monitoring-Architektur

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│ kube-state  │────→│              │────→│             │
│ -metrics    │     │  Prometheus  │     │  Grafana    │
└─────────────┘     │              │     │  (Dashboard)│
┌─────────────┐     │  (15d Ret.)  │     │             │
│ node        │────→│  (10Gi)      │     └─────────────┘
│ -exporter   │     └──────┬───────┘            │
└─────────────┘            │                    │
                    ┌──────▼───────┐     ┌──────▼──────┐
                    │ AlertManager │     │    Loki     │
                    │              │     │ (10Gi, 30d) │
                    └──────────────┘     └──────┬──────┘
                                                │
                                         ┌──────▼──────┐
                                         │  Promtail   │
                                         │ (DaemonSet) │
                                         └─────────────┘
```

## Konfiguration aendern

### Prometheus Values
```bash
vim infrastructure/monitoring/values.yaml
git add && git commit && git push
# Helm Release wird via ArgoCD aktualisiert
```

### Loki Values
```bash
vim infrastructure/logging/loki-values.yaml
```

### Grafana Datasource hinzufuegen
Direkt in Grafana UI: Configuration → Data Sources → Add data source
(Achtung: geht bei Pod-Restart verloren, besser in values.yaml konfigurieren)
