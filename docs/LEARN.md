# Lern-Notes — Was ich ueber jede Komponente wissen muss

## Kubernetes (k3s)

### Was ist k3s?
k3s ist eine leichtgewichtige Kubernetes-Distribution von Rancher/SUSE. Es ist ein einzelnes Binary (~70MB) das den kompletten Kubernetes-Stack enthaelt. Perfekt fuer Single-Node Setups, Edge Computing, oder VPS.

### Warum k3s statt k8s?
- **Ressourcen:** k3s braucht ~512MB RAM, volles k8s braucht ~2GB+
- **Installation:** Ein Befehl (`curl -sfL https://get.k3s.io | sh -`)
- **Built-in:** Traefik (Ingress), CoreDNS, local-path-provisioner, Metrics Server
- **Kompatibel:** 100% Kubernetes-konform (CNCF zertifiziert)

### Wichtige k3s-Pfade
```
/etc/rancher/k3s/k3s.yaml        # kubeconfig
/var/lib/rancher/k3s/storage/     # PVC-Daten (local-path)
/var/lib/rancher/k3s/server/      # etcd, Manifeste
/var/log/syslog                    # k3s Logs (oder journalctl -u k3s)
```

### Wichtige Befehle
```bash
sudo systemctl status k3s         # Laeuft k3s?
sudo systemctl restart k3s        # Neustart
kubectl get nodes                  # Node-Status
kubectl top nodes                  # Ressourcen-Verbrauch
```

---

## ArgoCD

### Was ist ArgoCD?
ArgoCD ist ein GitOps Continuous Delivery Tool fuer Kubernetes. Es ueberwacht ein Git-Repo und stellt sicher, dass der Cluster-Zustand dem Repo-Zustand entspricht.

### Wie funktioniert es?
1. ArgoCD pollt das Git-Repo (alle 3 Minuten)
2. Vergleicht den gewuenschten Zustand (Git) mit dem aktuellen (Cluster)
3. Bei Diff: automatisch syncen (wenn auto-sync aktiviert)
4. Self-Heal: manuelle Aenderungen werden rueckgaengig gemacht

### App-of-Apps Pattern
Statt jede Application einzeln zu erstellen, gibt es eine "Root" Application (`app-of-apps.yaml`) die auf den Ordner `argocd/applications/` zeigt. Jede YAML-Datei dort wird zu einer ArgoCD Application. So managed ArgoCD sich selbst.

### Sync-Waves
Annotations steuern die Reihenfolge: `argocd.argoproj.io/sync-wave: "1"`. Niedrigere Zahlen zuerst. Damit startet Authentik (Wave 1) vor Open WebUI (Wave 4) das Authentik als OIDC-Provider braucht.

### Wichtige Konzepte
- **Synced:** Git und Cluster sind identisch
- **OutOfSync:** Git hat Aenderungen die noch nicht im Cluster sind
- **Healthy:** Alle Pods/Services laufen
- **Progressing:** Rolling Update laeuft
- **Degraded:** Etwas ist kaputt
- **Prune:** Ressourcen die aus Git geloescht wurden, werden auch aus dem Cluster entfernt

---

## Traefik (Ingress Controller)

### Was macht Traefik?
Traefik ist der Reverse Proxy der alle eingehenden HTTPS-Anfragen an den richtigen Service weiterleitet. Es ist in k3s eingebaut.

### IngressRoute vs. Ingress
- **Ingress:** Standard-Kubernetes-Objekt (simpel, limitiert)
- **IngressRoute:** Traefik-eigenes CRD (maechtig, flexibel)
- Wir nutzen IngressRoutes weil sie Features wie Forward Auth, Middleware, TLS per Route unterstuetzen

### Aufbau einer IngressRoute
```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-service
spec:
  entryPoints: [websecure]         # Port 443
  routes:
    - match: Host(`my.domain.io`)  # Domain-Matching
      kind: Rule
      services:
        - name: my-service         # k8s Service Name
          port: 8080               # Service Port
  tls:
    secretName: my-tls             # TLS Zertifikat
```

---

## cert-manager

### Was macht cert-manager?
cert-manager automatisiert TLS-Zertifikate. Es erstellt, erneuert und verwaltet Let's Encrypt Zertifikate automatisch.

### Wie funktioniert es?
1. Du erstellst ein `Certificate`-Objekt mit dem gewuenschten Domain-Namen
2. cert-manager erstellt einen `CertificateRequest`
3. cert-manager erstellt eine ACME `Order` bei Let's Encrypt
4. Let's Encrypt prueft via HTTP-01 Challenge ob du die Domain kontrollierst
5. Zertifikat wird als Kubernetes Secret gespeichert
6. 30 Tage vor Ablauf: automatische Erneuerung

### ClusterIssuer
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@aymenmastouri.io
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: traefik
```

---

## Sealed Secrets

### Warum?
Kubernetes Secrets sind nur Base64-kodiert, nicht verschluesselt. Wenn du sie in Git committen wuerdest, kann jeder die Werte lesen. Sealed Secrets verschluesseln sie mit einem Public Key — nur der Controller im Cluster kann sie entschluesseln.

### Wie funktioniert es?
```
kubeseal (lokal)                    Sealed Secrets Controller (Cluster)
     │                                         │
     │ verschluesselt mit Public Key            │ entschluesselt mit Private Key
     │                                         │
     ▼                                         ▼
SealedSecret (in Git) ──── ArgoCD sync ───→ Secret (im Cluster)
```

---

## Authentik

### Was ist Authentik?
Open-Source Identity Provider (wie Keycloak, aber moderner). Unterstuetzt OIDC, SAML, LDAP, Forward Auth.

### Architektur
- **Server:** Django-App, API, Web UI. Laeuft Migrationen beim Start.
- **Worker:** Background Tasks (Celery). Braucht gleiche Env-Vars wie Server.
- **PostgreSQL:** Datenbank fuer User, Groups, Flows, Policies.

### Wichtig gelernt
- `args: [server]` verwenden, NICHT `command: [ak, server]` — sonst werden Migrationen uebersprungen
- Redis ist seit 2026.x nicht mehr noetig
- Volume Mount auf `/data` (nicht `/media`)
- Bootstrap-Variablen erstellen den initialen Admin-User

### Forward Auth
Traefik kann Anfragen zuerst an Authentik schicken. Wenn der User nicht eingeloggt ist → Redirect zur Login-Seite. Wenn eingeloggt → Request wird durchgelassen.

---

## Ollama

### Was ist Ollama?
Runtime fuer lokale LLMs. Laedt Modelle herunter und stellt eine OpenAI-kompatible API bereit.

### API
```
POST http://ollama:11434/api/generate    # Text Generation
POST http://ollama:11434/api/embeddings  # Embeddings
GET  http://ollama:11434/api/tags        # Modelle auflisten
```

### Modelle verwalten
```bash
kubectl exec -n apps deploy/ollama -- ollama pull qwen2.5:3b
kubectl exec -n apps deploy/ollama -- ollama list
kubectl exec -n apps deploy/ollama -- ollama rm <model>
```

---

## LiteLLM

### Was ist LiteLLM?
Unified Proxy fuer LLM-APIs. Routet Anfragen an verschiedene Backends (Ollama, OpenAI, Anthropic) ueber eine einheitliche OpenAI-kompatible API.

### Warum?
- Ein API-Endpoint fuer alle Modelle
- API-Key Management
- Rate Limiting
- Fallback-Routing (wenn Ollama down → OpenAI)
- Usage Tracking

### API
```
POST http://litellm:4000/v1/chat/completions  # Wie OpenAI API
POST http://litellm:4000/v1/embeddings         # Embeddings
GET  http://litellm:4000/v1/models             # Verfuegbare Modelle
```

---

## Qdrant

### Was ist Qdrant?
Vector-Datenbank fuer Similarity Search. Speichert Embeddings und findet aehnliche Dokumente.

### Wofuer brauchen wir das?
RAG (Retrieval-Augmented Generation): Bevor ein LLM eine Frage beantwortet, suchen wir relevante Dokumente in Qdrant und geben sie dem LLM als Kontext.

### API
```
PUT  http://qdrant:6333/collections/<name>     # Collection erstellen
POST http://qdrant:6333/collections/<name>/points  # Punkte einfuegen
POST http://qdrant:6333/collections/<name>/points/search  # Suchen
```

---

## Langfuse

### Was ist Langfuse?
LLM Observability Platform. Trackt jeden LLM-Aufruf: Input, Output, Tokens, Latency, Kosten.

### Warum?
- Debugging: Warum hat das LLM Mist gebaut?
- Kosten-Tracking: Wie viele Tokens verbrauche ich?
- Quality: A/B-Testing verschiedener Prompts
- Compliance: Audit-Trail aller LLM-Aufrufe

### Wichtig
- v2 verwenden (v3 braucht ClickHouse)
- Integration via Environment Variables im SDLC Pilot Backend

---

## MLflow

### Was ist MLflow?
Experiment Tracking Platform. Speichert Parameter, Metriken und Artifacts von ML/AI Experimenten.

### Wofuer?
- Prompt-Versionen tracken
- Ergebnisse verschiedener Modelle vergleichen
- Artifacts (generierte Dokumente, Reports) speichern

### Wichtig
- Braucht `psycopg2-binary` (nicht im Base Image)
- `--allowed-hosts` Flag existiert nicht (einfach weglassen)

---

## Prometheus + Grafana + Loki

### Prometheus
- **Pull-Modell:** Prometheus scrapt /metrics Endpoints (alle 30s)
- **PromQL:** Abfragesprache fuer Metriken
- **Retention:** 15 Tage (konfigurierbar)
- **Storage:** 10Gi PVC

### Grafana
- **Dashboards:** Vorgefertigte + eigene
- **3 Datasources:** Prometheus, Loki, AlertManager
- **Alerts:** Grafana kann auch eigene Alerts erstellen

### Loki
- **Log Aggregation:** Wie Elasticsearch, aber leichtgewichtiger
- **LogQL:** Abfragesprache (aehnlich PromQL)
- **Labels:** Logs werden nach Labels (namespace, pod, container) indiziert
- **SingleBinary Mode:** Alle Komponenten in einem Pod (gut fuer Single-Node)

### Promtail
- **DaemonSet:** Laeuft auf jedem Node
- **Sammelt:** stdout/stderr aller Container
- **Enrichment:** Fuegt Kubernetes Labels hinzu (namespace, pod, container)
- **Schickt an:** Loki
