# Lens Guide — Kubernetes IDE

## Was ist Lens?

Lens ist eine Desktop-App (Mac/Windows/Linux) die dir eine grafische Oberflaeche fuer deinen Kubernetes-Cluster gibt. Statt `kubectl get pods` tippst du — du siehst alles live, klickst dich durch Pods, Logs, Metriken.

**Download:** https://k8slens.dev/

## Setup

### 1. kubeconfig vom VPS holen
```bash
# Auf dem VPS:
sudo cat /etc/rancher/k3s/k3s.yaml

# Server-Adresse aendern (von 127.0.0.1 auf VPS-IP):
# server: https://51.195.116.255:6443
```

### 2. Lokal speichern
```bash
# Auf deinem Mac:
mkdir -p ~/.kube
# Inhalt von k3s.yaml einfuegen (mit geaenderter Server-Adresse)
vim ~/.kube/config
```

### 3. In Lens importieren
- Lens oeffnen → File → Add Cluster
- kubeconfig auswaehlen oder einfuegen
- Connect

## Navigation

### Workloads
- **Pods** — Alle laufenden Container. Klick auf einen Pod zeigt Details, Logs, Shell.
- **Deployments** — Zeigt gewuenschte vs. aktuelle Replicas. Restart-Button.
- **StatefulSets** — Fuer Postgres (authentik-postgres, langfuse-postgres, mlflow-postgres)

### Network
- **Services** — Alle ClusterIP Services (interne DNS-Namen)
- **Ingresses** — Traefik IngressRoutes (erscheinen hier ggf. nicht weil CRDs)

### Storage
- **Persistent Volume Claims** — Alle 14 PVCs mit Status und Groesse
- **Persistent Volumes** — Die tatsaechlichen Volumes auf dem Node

### Configuration
- **ConfigMaps** — nginx-config fuer SDLC Pilot, etc.
- **Secrets** — Entschluesselte Secrets (Base64 dekodiert in Lens)

### Custom Resources
- **IngressRoute** — Traefik Routing-Regeln
- **Certificate** — cert-manager TLS Zertifikate
- **Application** — ArgoCD Applications

## Nuetzliche Filter

### Nach Namespace filtern
Oben links im Namespace-Dropdown:
- `apps` — Alle deine Services
- `monitoring` — Prometheus, Grafana, Loki
- `infra` — ArgoCD, Sealed Secrets
- `cert-manager` — TLS Automation

### Nach Labels filtern
In der Pod-Liste → Filter-Icon:
- `app.kubernetes.io/part-of=ai-lab` — Alle AI Lab Services
- `app.kubernetes.io/component=backend` — Nur Backends
- `app.kubernetes.io/name=ollama` — Nur Ollama

## Taeglich nuetzliche Aktionen

### Logs live anschauen
Pod → Klick → Logs-Tab → "Follow" aktivieren

### In Pod Shell oeffnen
Pod → Klick → Shell-Tab → Terminal oeffnet sich

### Pod restarten
Deployment → Klick → Restart-Button (oben rechts)

### Resource Usage sehen
Pod → Klick → zeigt CPU/RAM Graphen (wenn Metrics Server laeuft)

### Events pruefen
Events-Tab (links) → filtert nach Namespace → zeigt Warnungen, Errors

## Lens vs. kubectl

| Aufgabe | kubectl | Lens |
|---------|---------|------|
| Pods auflisten | `kubectl get pods -n apps` | Workloads → Pods |
| Logs lesen | `kubectl logs deploy/ollama -n apps` | Pod → Logs Tab |
| Shell oeffnen | `kubectl exec -it pod -- sh` | Pod → Shell Tab |
| Events | `kubectl get events -n apps` | Events Tab |
| Secret lesen | `kubectl get secret -o jsonpath...` | Configuration → Secrets → Klick |
| Deployment restarten | `kubectl rollout restart deploy/...` | Deployment → Restart |

**Empfehlung:** Lens fuer taegliches Monitoring und Debugging. kubectl fuer Scripting und Automation.

## Tipps

- **Hotbar:** Haeufig genutzte Ressourcen auf die Hotbar ziehen (unten)
- **Multi-Cluster:** Du kannst mehrere Cluster gleichzeitig verwalten
- **Extensions:** Lens hat ein Extension-System (z.B. fuer Prometheus-Integration)
- **Dark Mode:** Preferences → Appearance → Theme
