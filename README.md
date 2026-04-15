# k8s-manifests

Kubernetes manifests for the AI Lab platform. Managed by ArgoCD (GitOps).

## Structure

```
apps/                    # Application workloads
infrastructure/          # Cluster infrastructure (cert-manager, sealed-secrets, monitoring)
argocd/                  # ArgoCD configuration (app-of-apps, projects, applications)
```

## GitOps Workflow

1. Edit manifests in this repo
2. Push to `main`
3. ArgoCD detects changes and syncs to cluster

## Cluster

- **Platform:** k3s on OVH VPS
- **Ingress:** Traefik (k3s built-in)
- **TLS:** cert-manager + Let's Encrypt
- **Secrets:** Sealed Secrets (Bitnami)
- **GitOps:** ArgoCD
