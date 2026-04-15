# GitOps Workflow

## Grundprinzip

```
Code aendern → git push → ArgoCD erkennt Diff → Cluster wird aktualisiert
```

**Alles** was im Cluster laeuft, ist durch YAML-Dateien in diesem Repo definiert. Manuelle `kubectl apply` Befehle sind verboten (ausser fuer Debugging). ArgoCD hat Self-Heal aktiviert — manuelle Aenderungen werden automatisch rueckgaengig gemacht.

## Wie deploye ich eine Aenderung?

### 1. Manifest aendern
```bash
# Beispiel: Ollama Memory-Limit erhoehen
vim apps/ollama/deployment.yaml
```

### 2. Committen und pushen
```bash
git add apps/ollama/deployment.yaml
git commit -m "feat(ollama): increase memory limit to 4Gi"
git push
```

### 3. ArgoCD synct automatisch
ArgoCD pollt alle 3 Minuten. Fuer sofortigen Sync:
```bash
kubectl -n infra annotate application ollama argocd.argoproj.io/refresh=hard --overwrite
```

### 4. Pruefen
```bash
kubectl get application ollama -n infra
kubectl get pods -n apps -l app.kubernetes.io/name=ollama
```

## Haeufige Aenderungen

### Image-Version aendern
```yaml
# In deployment.yaml:
image: ghcr.io/goauthentik/server:2026.2.2  # ← Version aendern
```
Commit + Push → ArgoCD rollt automatisch aus.

### Environment Variable hinzufuegen
```yaml
# In deployment.yaml, unter env:
- name: NEW_VAR
  value: "new-value"
```

### Secret hinzufuegen/aendern
```bash
# 1. Secret erstellen
kubectl create secret generic my-secret \
  --from-literal=KEY=value \
  --dry-run=client -o yaml > /tmp/secret.yaml

# 2. Verschluesseln
kubeseal --format yaml < /tmp/secret.yaml > apps/<service>/sealed-secret.yaml

# 3. Committen
git add apps/<service>/sealed-secret.yaml
git commit -m "feat(<service>): add new secret"
git push

# 4. Aufraumen
rm /tmp/secret.yaml
```

### Neuen Service hinzufuegen

1. Ordner erstellen: `apps/<name>/`
2. Manifests erstellen:
   - `deployment.yaml` (Deployment + Service + PVC)
   - `ingressroute.yaml` (Traefik IngressRoute + Certificate)
   - `sealed-secret.yaml` (falls Secrets noetig)
3. ArgoCD Application erstellen: `argocd/applications/<name>.yaml`
4. App-of-Apps referenziert den Ordner automatisch (da `applications/` als Source)
5. Commit + Push

### ArgoCD Application Template
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <service-name>
  namespace: infra
  annotations:
    argocd.argoproj.io/sync-wave: "3"  # Wave 0-5
spec:
  project: ai-lab
  source:
    repoURL: https://github.com/aymenmastouri/k8s-manifests.git
    targetRevision: main
    path: apps/<service-name>
  destination:
    server: https://kubernetes.default.svc
    namespace: apps
  syncPolicy:
    automated:
      prune: true       # Geloeschte Ressourcen werden entfernt
      selfHeal: true    # Manuelle Aenderungen werden rueckgaengig gemacht
    syncOptions:
      - CreateNamespace=true
```

## CI/CD Pipeline (SDLC Pilot)

SDLC Pilot hat eine GitHub Actions Pipeline die bei Push auf `main` im `aicodegencrew` Repo automatisch baut:

```
Push auf aicodegencrew/main
  → GitHub Actions
    → Build Backend Docker Image
    → Build Frontend Docker Image
    → Push zu GHCR (:latest + :sha)
  → kubectl rollout restart (manuell oder Webhook)
```

### Nach Image-Build deployen
```bash
kubectl rollout restart deployment sdlc-pilot-backend -n apps
kubectl rollout restart deployment sdlc-pilot-frontend -n apps
```

## Standard-Labels

Jede Ressource muss diese Labels haben:
```yaml
labels:
  app.kubernetes.io/name: <service-name>      # z.B. ollama
  app.kubernetes.io/component: <component>     # z.B. server, worker, frontend
  app.kubernetes.io/part-of: ai-lab            # Immer "ai-lab"
  app.kubernetes.io/managed-by: argocd         # Immer "argocd"
```

**Warum:** Labels ermoeglichen Filterung in Lens, Prometheus ServiceMonitors, und `kubectl get pods -l ...` Queries.

## Sync-Waves erklaert

ArgoCD deployed Services in einer definierten Reihenfolge:

| Wave | Services | Warum |
|------|----------|-------|
| 0 | Portal, Portfolio | Keine Dependencies, sofort starten |
| 1 | Authentik | SSO-Provider muss vor OIDC-Clients laufen |
| 2 | Ollama, Qdrant | Basis-Infra fuer AI Services |
| 3 | LiteLLM, Langfuse, MLflow | Brauchen Ollama/Qdrant |
| 4 | Open WebUI | Braucht LiteLLM + Authentik OIDC |
| 5 | SDLC Pilot | Braucht alles |

## Rollback

### Letzte Aenderung rueckgaengig machen
```bash
git revert HEAD
git push
# ArgoCD synct automatisch zurueck
```

### Auf bestimmten Commit zurueck
```bash
# In ArgoCD UI: Application → History → Rollback
# Oder:
git revert <commit-hash>
git push
```

**Wichtig:** Nie `git reset --hard` + `git push --force` auf `main`. Immer `git revert` verwenden.
