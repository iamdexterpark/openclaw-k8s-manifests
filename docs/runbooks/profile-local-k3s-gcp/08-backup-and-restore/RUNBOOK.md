# Runbook 08 — Backup & Restore

> **Target Environment** (mandatory — a runbook that doesn't declare its env is a trap)
> | | |
> |---|---|
> | **Deployment profile** | `profile-local-k3s-gcp` (primary) |
> | **Substrate** | self-hosted K3s |
> | **Cloud services used** | GCS (versioned bucket: state prefix + restic repo) |
> | **Identity model** | GCP Workload Identity; restic password from a materialized Secret |
> | **What changes under a different profile** | the object-store URL scheme (`gs:` → `s3:` → `azure:`) and the versioning toggle command |

**Goal:** know exactly how the corpus is snapshotted, how to restore it (single object or whole
corpus), and how to read the weekly drill — because a backup nobody restored is not a backup
([ADR-0004](../../adr/0004-backup-restic-over-velero.md)).
**Time:** ~10 min (restore) · **Risk:** med · **Reversible:** yes

## How backups happen (automatic)

The platform layer (Runbook 03) runs two CronJobs:

- `state-backup` — hourly: `restic backup` of the synced state mirror, then
  `forget --keep-hourly 24 --keep-daily 7 --keep-weekly 4 --prune`. **Client-encrypted** — GCS only
  holds ciphertext.
- `restore-drill` — weekly: `restic check` + real restore + smoke test.

## Restore — whole corpus (restic)

> **Scale the single writer to zero first** — never two writers
> ([ADR-0001](../../adr/0001-workload-primitive-deployment-over-statefulset.md)).

```bash
kubectl -n <id> scale deploy/<id>-workload --replicas=0
restic restore latest --target /restore --tag fleet-state    # or a specific snapshot id
# sync /restore back to the agent's GCS state prefix, then:
kubectl -n <id> scale deploy/<id>-workload --replicas=1
kubectl -n <id> rollout status deploy/<id>-workload --timeout=180s
```

## Restore — a single object (GCS object versioning)

```bash
gcloud storage ls --all-versions "gs://edge-agent-state/agents/<id>/memory/2026-06-18.md"
gcloud storage cp "gs://edge-agent-state/agents/<id>/memory/2026-06-18.md#GENERATION" \
  "gs://edge-agent-state/agents/<id>/memory/2026-06-18.md"
```

## Verification

```bash
kubectl -n platform get job -l app.kubernetes.io/name=restore-drill   # latest drill Complete
kubectl -n platform logs job/<latest-restore-drill> | grep 'restore-drill: OK'
# after a manual restore:
kubectl -n <id> port-forward svc/<id>-workload 8080:80 >/dev/null 2>&1 &
curl -sf localhost:8080/healthz && echo "  restored agent healthy"
```

## Rollback

A restore is itself the rollback. If a restore is wrong, restore a *different* snapshot — every
hourly/daily/weekly snapshot within retention is selectable by id.

## Notes / Gotchas

- If `restore-drill` goes red, treat **all** backups as unverified until it's green again — page the
  operator (HLD risk R6).
- The restic repo password is a top-tier secret: lose it and the encrypted backups are unrecoverable.
