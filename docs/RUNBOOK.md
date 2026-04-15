# Runbook — Operations Guide

## Service neu starten

### Einzelnen Service restarten
```bash
kubectl rollout restart deployment <name> -n apps
```

### Alle Services restarten (nach VPS-Reboot)
k3s startet automatisch alle Pods. Falls noetig:
```bash
kubectl rollout restart deployment -n apps
```

### Authentik komplett neu starten
```bash
kubectl -n apps scale deploy authentik-server authentik-worker --replicas=0
# Warten bis Pods weg sind
kubectl -n apps scale deploy authentik-server authentik-worker --replicas=1
```

## Logs anschauen

### Live-Logs eines Service
```bash
kubectl logs -n apps deploy/<name> --tail=50 -f
```

### Logs aller Pods eines Service
```bash
kubectl logs -n apps -l app.kubernetes.io/name=<name> --tail=50
```

### Logs via Grafana/Loki (empfohlen)
1. Oeffne https://grafana.aymenmastouri.io
2. Explore → Loki Datasource
3. Query: `{namespace="apps", pod=~".*<name>.*"}`

### Haeufige Log-Queries
```logql
# Alle Fehler in apps
{namespace="apps"} |= "error" | logfmt

# Authentik Startup
{namespace="apps", pod=~"authentik-server.*"}

# SDLC Pilot Backend
{namespace="apps", pod=~"sdlc-pilot-backend.*"}

# ArgoCD Sync-Fehler
{namespace="infra", pod=~"argocd-application-controller.*"} |= "error"
```

## Pods debuggen

### Pod-Status pruefen
```bash
kubectl get pods -n apps
kubectl describe pod <pod-name> -n apps
```

### In einen Pod rein (Shell)
```bash
kubectl exec -it -n apps deploy/<name> -- /bin/sh
```

### Events anschauen
```bash
kubectl get events -n apps --sort-by=.lastTimestamp | tail -20
```

## Backups

### Qdrant Snapshot erstellen
```bash
# Snapshot aller Collections
kubectl exec -n apps deploy/qdrant -- \
  curl -s -X POST http://localhost:6333/snapshots

# Snapshot einer Collection
kubectl exec -n apps deploy/qdrant -- \
  curl -s -X POST http://localhost:6333/collections/<name>/snapshots
```

### PostgreSQL Backup (alle Datenbanken)
```bash
# Authentik DB
kubectl exec -n apps authentik-postgres-0 -- \
  pg_dump -U authentik authentik > authentik-backup.sql

# Langfuse DB
kubectl exec -n apps langfuse-postgres-0 -- \
  pg_dump -U langfuse langfuse > langfuse-backup.sql

# MLflow DB
kubectl exec -n apps mlflow-postgres-0 -- \
  pg_dump -U mlflow mlflow > mlflow-backup.sql
```

### PVC-Daten sichern
```bash
# Alle PVC-Daten liegen unter:
ls /var/lib/rancher/k3s/storage/

# Komplettes Backup
sudo tar czf /tmp/k3s-storage-backup.tar.gz /var/lib/rancher/k3s/storage/
```

### Ollama Modelle auflisten
```bash
kubectl exec -n apps deploy/ollama -- ollama list
```

## Restore

### PostgreSQL Restore
```bash
# Scale Service auf 0
kubectl -n apps scale deploy <service> --replicas=0

# Restore
cat backup.sql | kubectl exec -i -n apps <postgres-pod> -- psql -U <user> <db>

# Scale zurueck
kubectl -n apps scale deploy <service> --replicas=1
```

### Qdrant Restore
```bash
# Snapshot wiederherstellen
kubectl exec -n apps deploy/qdrant -- \
  curl -s -X PUT http://localhost:6333/snapshots/recover \
  -H "Content-Type: application/json" \
  -d '{"location": "/qdrant/snapshots/<snapshot-file>"}'
```

## Sealed Secrets

### Neues Secret erstellen
```bash
# 1. Normales Secret YAML erstellen (NICHT committen!)
kubectl create secret generic <name> \
  --from-literal=KEY=value \
  --dry-run=client -o yaml > secret.yaml

# 2. Verschluesseln
kubeseal --format yaml < secret.yaml > sealed-secret.yaml

# 3. Sealed Secret committen
mv sealed-secret.yaml apps/<service>/sealed-secret.yaml
git add && git commit && git push

# 4. Unverschluesseltes Secret loeschen!
rm secret.yaml
```

### Secret-Wert lesen
```bash
kubectl get secret <name> -n apps -o jsonpath='{.data.<key>}' | base64 -d
```

## TLS-Zertifikate

### Status pruefen
```bash
kubectl get certificates -A
```

### Zertifikat erneuern erzwingen
```bash
kubectl delete certificate <name> -n apps
# cert-manager erstellt automatisch ein neues
```

### ACME-Fehler debuggen
```bash
kubectl describe certificate <name> -n apps
kubectl get certificaterequest -n apps
kubectl describe order -n apps
```

## ArgoCD

### Sync-Status pruefen
```bash
kubectl get applications -n infra
```

### Force Sync
```bash
kubectl -n infra annotate application <name> argocd.argoproj.io/refresh=hard --overwrite
```

### ArgoCD Web UI
- URL: https://argocd.aymenmastouri.io (falls IngressRoute existiert)
- Oder: `kubectl port-forward svc/argocd-server -n infra 8080:443`
- Passwort: `kubectl -n infra get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`

## Ollama

### Modell herunterladen
```bash
kubectl exec -n apps deploy/ollama -- ollama pull qwen2.5:3b
kubectl exec -n apps deploy/ollama -- ollama pull nomic-embed-text
```

### Modell loeschen
```bash
kubectl exec -n apps deploy/ollama -- ollama rm <model>
```

### Modelle auflisten
```bash
kubectl exec -n apps deploy/ollama -- ollama list
```

## Haeufige Probleme

### Pod in CrashLoopBackOff
```bash
# 1. Logs pruefen
kubectl logs -n apps <pod> --previous

# 2. Events pruefen
kubectl describe pod <pod> -n apps | tail -20

# 3. Haeuige Ursachen:
#    - Secret fehlt → Sealed Secret pruefen
#    - PVC Pending → Storage pruefen
#    - OOMKilled → Resource Limits erhoehen
```

### ImagePullBackOff
```bash
# GHCR Credentials pruefen
kubectl get secret ghcr-credentials -n apps

# Falls fehlt:
kubectl create secret docker-registry ghcr-credentials \
  -n apps \
  --docker-server=ghcr.io \
  --docker-username=aymenmastouri \
  --docker-password=<GITHUB_TOKEN>
```

### PVC Pending
```bash
kubectl describe pvc <name> -n apps
# Meist: Speicherplatz voll
df -h /var/lib/rancher/k3s/storage/
```

### Node NotReady
```bash
# k3s Service pruefen
sudo systemctl status k3s
sudo journalctl -u k3s --tail=50

# k3s neustarten
sudo systemctl restart k3s
```
