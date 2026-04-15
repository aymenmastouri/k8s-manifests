# Disaster Recovery — Was tun wenn alles brennt

## Severity-Stufen

| Stufe | Situation | Aktion |
|-------|-----------|--------|
| 1 - Low | Ein Service down | Pod/Deployment restarten |
| 2 - Medium | Mehrere Services down | k3s restarten |
| 3 - High | Node nicht erreichbar | VPS Recovery, SSH-Zugang wiederherstellen |
| 4 - Critical | Alles weg | VPS neu aufsetzen, Cluster neu bauen |

---

## Stufe 1: Einzelner Service down

### Symptom: Pod CrashLoopBackOff
```bash
# 1. Ursache finden
kubectl logs -n apps <pod-name> --previous
kubectl describe pod <pod-name> -n apps

# 2. Haeuige Ursachen + Fixes:
# Secret fehlt:
kubectl get secrets -n apps | grep <service>

# OOMKilled (zu wenig RAM):
# → Resource Limits in deployment.yaml erhoehen

# Image Pull Error:
kubectl get secret ghcr-credentials -n apps
# Falls weg: neu erstellen (siehe RUNBOOK.md)

# 3. Restart
kubectl rollout restart deployment <name> -n apps
```

### Symptom: Service antwortet nicht (aber Pod Running)
```bash
# Health-Check pruefen
kubectl exec -n apps deploy/<name> -- curl -s http://localhost:<port>/health

# Readiness Probe pruefen
kubectl describe pod <pod-name> -n apps | grep -A5 "Readiness"

# Service → Pod Verbindung pruefen
kubectl get endpoints <service-name> -n apps
```

---

## Stufe 2: Mehrere Services down

### k3s restarten
```bash
sudo systemctl restart k3s
# Warten bis alle Pods wieder laufen (2-5 Minuten)
kubectl get pods -A | grep -v Running
```

### ArgoCD Force Sync aller Apps
```bash
for app in portal portfolio authentik ollama qdrant litellm langfuse mlflow open-webui sdlc-pilot; do
  kubectl -n infra annotate application $app argocd.argoproj.io/refresh=hard --overwrite
done
```

### Alle Deployments restarten
```bash
kubectl rollout restart deployment -n apps
```

---

## Stufe 3: Node nicht erreichbar

### SSH geht noch
```bash
# Auf dem VPS:
sudo systemctl status k3s
sudo journalctl -u k3s --tail=100

# k3s komplett neu starten
sudo systemctl restart k3s

# Falls k3s nicht startet:
sudo k3s check-config
```

### SSH geht nicht
1. OVH Console einloggen: https://www.ovh.com/manager/
2. VPS → KVM Console (Web-basierte Konsole)
3. Netzwerk pruefen: `ip addr`, `ping 8.8.8.8`
4. Firewall pruefen: `sudo iptables -L -n`
5. SSH-Dienst pruefen: `sudo systemctl status sshd`

### VPS haengt komplett
1. OVH Manager → VPS → Reboot (Soft Reboot)
2. Falls nicht: Hard Reboot
3. Nach Reboot: k3s startet automatisch, alle Pods kommen zurueck

---

## Stufe 4: Alles weg — Kompletter Neuaufbau

### Was du brauchst
- Zugang zum OVH VPS (SSH oder KVM Console)
- Das `k8s-manifests` GitHub Repo (enthaelt alles)
- Sealed Secrets Private Key (WICHTIG: ohne diesen Key koennen verschluesselte Secrets nicht wiederhergestellt werden!)

### Schritt 1: k3s installieren
```bash
curl -sfL https://get.k3s.io | sh -
# Warten bis Node Ready
kubectl get nodes
```

### Schritt 2: ArgoCD installieren
```bash
kubectl create namespace infra
kubectl apply -n infra -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.14.12/manifests/install.yaml
```

### Schritt 3: cert-manager installieren
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml
# ClusterIssuer erstellen (siehe infrastructure/cert-manager/)
```

### Schritt 4: Sealed Secrets installieren
```bash
helm install sealed-secrets sealed-secrets/sealed-secrets -n infra
```

### Schritt 5: Sealed Secrets Key wiederherstellen
```bash
# OHNE diesen Schritt koennen bestehende SealedSecrets nicht entschluesselt werden!
# Key aus Backup einspielen:
kubectl apply -f sealed-secrets-key-backup.yaml -n infra
kubectl rollout restart deployment sealed-secrets-controller -n infra
```

### Schritt 6: GHCR Credentials erstellen
```bash
kubectl create namespace apps
kubectl create secret docker-registry ghcr-credentials \
  -n apps \
  --docker-server=ghcr.io \
  --docker-username=aymenmastouri \
  --docker-password=<GITHUB_TOKEN>
```

### Schritt 7: App-of-Apps deployen
```bash
kubectl apply -f argocd/projects/ai-lab.yaml -n infra
kubectl apply -f argocd/app-of-apps.yaml -n infra
# ArgoCD synct jetzt automatisch alle Services
```

### Schritt 8: Monitoring installieren
```bash
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f infrastructure/monitoring/values.yaml

helm install loki grafana/loki \
  -n monitoring \
  -f infrastructure/logging/loki-values.yaml

helm install promtail grafana/promtail \
  -n monitoring \
  -f infrastructure/logging/promtail-values.yaml
```

### Schritt 9: Warten und pruefen
```bash
# Alle Pods pruefen
kubectl get pods -A | grep -v Running

# Alle Zertifikate pruefen
kubectl get certificates -A

# Alle ArgoCD Apps pruefen
kubectl get applications -n infra
```

---

## Backup-Strategie

### Was muss gesichert werden?

| Was | Wo | Wie oft | Wie |
|-----|-----|---------|-----|
| PostgreSQL Daten | authentik-postgres, langfuse-postgres, mlflow-postgres | Taeglich | `pg_dump` |
| Qdrant Collections | qdrant-storage PVC | Woechentlich | Qdrant Snapshot API |
| Sealed Secrets Key | sealed-secrets-controller Secret | Einmal (nach Installation) | `kubectl get secret` |
| Git Repo | GitHub | Automatisch | Git push |
| Ollama Modelle | ollama-models PVC | Nicht noetig | Modelle koennen neu gedownloadet werden |

### Sealed Secrets Key sichern (KRITISCH!)
```bash
# DAS IST DER WICHTIGSTE BACKUP!
# Ohne diesen Key sind alle SealedSecrets im Repo wertlos.
kubectl get secret -n infra -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-key-backup.yaml

# Sicher aufbewahren (NICHT in Git!)
# z.B. verschluesselt in einem Passwort-Manager
```

### Automatisches DB-Backup Script
```bash
#!/bin/bash
DATE=$(date +%Y%m%d)
BACKUP_DIR=/tmp/backups/$DATE
mkdir -p $BACKUP_DIR

# Authentik
kubectl exec -n apps authentik-postgres-0 -- \
  pg_dump -U authentik authentik > $BACKUP_DIR/authentik.sql

# Langfuse
kubectl exec -n apps langfuse-postgres-0 -- \
  pg_dump -U langfuse langfuse > $BACKUP_DIR/langfuse.sql

# MLflow
kubectl exec -n apps mlflow-postgres-0 -- \
  pg_dump -U mlflow mlflow > $BACKUP_DIR/mlflow.sql

# Komprimieren
tar czf /tmp/backups/db-backup-$DATE.tar.gz $BACKUP_DIR/

echo "Backup done: /tmp/backups/db-backup-$DATE.tar.gz"
```

---

## Checkliste nach Recovery

- [ ] Alle Pods Running? (`kubectl get pods -A | grep -v Running`)
- [ ] Alle Zertifikate Valid? (`kubectl get certificates -A`)
- [ ] Alle ArgoCD Apps Synced? (`kubectl get applications -n infra`)
- [ ] Authentik Login funktioniert? (https://auth.aymenmastouri.io)
- [ ] Open WebUI erreichbar? (https://chat.aymenmastouri.io)
- [ ] SDLC Pilot Frontend + Backend? (https://sdlc.aymenmastouri.io)
- [ ] Grafana Dashboards laden? (https://grafana.aymenmastouri.io)
- [ ] Loki Logs fliessen? (Grafana → Explore → Loki)
- [ ] Ollama Modelle geladen? (`kubectl exec deploy/ollama -n apps -- ollama list`)
