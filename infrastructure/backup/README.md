# AI Lab — Backup Strategy

## 1. Postgres daily dumps (automated)

`postgres-backup.yaml` deploys a CronJob in the `apps` namespace that runs
**daily at 02:15 Europe/Berlin** and writes custom-format pg_dump files to the
`ai-lab-backups` PVC (10 Gi, local-path):

```
/backups/
├── authentik/<timestamp>.dump
├── langfuse/<timestamp>.dump
└── mlflow/<timestamp>.dump
```

Retention: **7 days** (older dumps auto-pruned).

### Manual trigger

```bash
kubectl -n apps create job --from=cronjob/postgres-backup postgres-backup-manual
kubectl -n apps logs -f job/postgres-backup-manual
```

### Restore a database

```bash
# 1. copy the dump off the cluster (or use a pod that mounts the PVC)
kubectl -n apps run restore --rm -it --restart=Never \
  --image=postgres:16-alpine --overrides='
{
  "spec": {
    "containers": [{
      "name": "restore", "image": "postgres:16-alpine",
      "command": ["sh", "-c", "sleep 3600"],
      "volumeMounts": [{"name": "b", "mountPath": "/backups"}]
    }],
    "volumes": [{"name": "b", "persistentVolumeClaim": {"claimName": "ai-lab-backups"}}]
  }
}' -- sh

# inside the pod, e.g. restore langfuse:
PGPASSWORD=$(kubectl -n apps get secret langfuse-secrets -o jsonpath='{.data.LANGFUSE_DB_PASSWORD}' | base64 -d)
pg_restore -h langfuse-postgres -U langfuse -d langfuse -c /backups/langfuse/<ts>.dump
```

---

## 2. SealedSecrets master key (critical — manual off-cluster backup)

**Why**: the controller's private key is the only way to decrypt every
`SealedSecret` in the repo. Losing it = losing access to all secrets. Stealing
it = full compromise. Do **not** commit this to git.

### Export the key

```bash
kubectl -n infra get secret \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-key-$(date -u +%Y%m%d).yaml
```

Store the output **off the cluster** (1Password vault, encrypted USB drive,
hardware security module — somewhere the VPS cannot reach).

### Verify backup is complete

```bash
grep -c 'tls.key:' sealed-secrets-key-*.yaml  # should be ≥ 1
```

### Restore on a new cluster

```bash
# 1. reinstall sealed-secrets controller (don't let it generate a key)
helm install sealed-secrets sealed-secrets/sealed-secrets -n infra \
  --set-file keyrenewperiod=0

# 2. apply the backed-up key before anything else
kubectl apply -f sealed-secrets-key-YYYYMMDD.yaml

# 3. restart the controller so it picks up the key
kubectl -n infra rollout restart deploy/sealed-secrets-controller
```

---

## 3. What's NOT yet backed up

- **Ollama models** (20 GiB) — easy to re-pull, skipped
- **Qdrant snapshots** — Qdrant has its own snapshot API; wire it up if
  embeddings should survive a disaster
- **MLflow artifacts** (5 GiB local path) — re-ingest from experiments if lost
- **Authentik media / custom templates** — none configured, nothing to back up

---

## 4. Off-site sync (recommended, not automated here)

For a production setup, rsync `/var/lib/rancher/k3s/storage/<pvc-id>` of the
`ai-lab-backups` PVC to S3/Backblaze/restic nightly from the host. The local
PVC alone doesn't survive a VPS loss.
