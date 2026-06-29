# Runbook 07 — Decommission an Agent

> **Target Environment** (mandatory — a runbook that doesn't declare its env is a trap)
> | | |
> |---|---|
> | **Deployment profile** | `_common` — profile-independent (the K8s teardown is identical) |
> | **Substrate** | any K8s cluster reachable by `kubectl` |
> | **Cloud services used** | object storage (final archive + TTL) |
> | **Identity model** | your cluster credential + object-store write/lifecycle permission |
> | **What changes under a different profile** | only the object-store CLI/TTL command (GCS vs S3 vs Azure Blob) — see that profile's 08 runbook |

**Goal:** retire one agent cleanly — final state archived, cluster resources gone, **no orphaned
cloud spend** left behind.
**Time:** ~10 min · **Risk:** med (destructive) · **Reversible:** partially (archive first!)

## Prerequisites

- A confirmed decision to retire this agent (this is destructive).
- A final snapshot taken (Runbook 08) **before** anything is deleted.

## Steps

### 1. Take a final snapshot

```bash
# trigger the backup CronJob once, out of band, and confirm it succeeded
kubectl -n platform create job --from=cronjob/state-backup final-archive-<id>
kubectl -n platform wait --for=condition=complete job/final-archive-<id> --timeout=300s
```

### 2. Delete the namespace (config + secret + workload, one shot)

```bash
kubectl delete ns <id>     # namespace-per-agent → one command removes everything in-cluster
```

### 3. Retire the cloud state (no orphaned spend)

```bash
# Set a TTL / lifecycle rule on the agent's state prefix so it ages out, OR archive + delete.
# (Profile-specific command — GCS example; see the profile 08 runbook for the exact form.)
gcloud storage rm --recursive "gs://edge-agent-state/agents/<id>/"   # after archive confirmed
```

### 4. Retire the secrets

```bash
# Remove the agent's secret-manager key paths so you're not paying for / exposing stale versions.
gcloud secrets delete agents/<id>/gateway-auth-password --quiet
gcloud secrets delete agents/<id>/model-api-key --quiet
```

### 5. Archive the repo / overlay

Remove `manifests/overlays/<id>/` in a PR and archive the agent's persona repo.

## Verification

```bash
kubectl get ns <id> 2>&1 | grep -q NotFound && echo "namespace gone"
gcloud storage ls "gs://edge-agent-state/agents/<id>/" 2>&1 | grep -q 'not' && echo "state retired"
gcloud secrets list --filter="name:agents/<id>" --format='value(name)'   # should be empty
```

**No-orphaned-spend check:** confirm the state prefix, secret versions, and any agent-specific
Pub/Sub subscription are gone — these are the line items that quietly keep billing.

## Rollback

There is no rollback after deletion — that's why **step 1 (final archive) is mandatory**. To bring
the agent back, redeploy its overlay (Runbook 06) and restore state from the final snapshot
(Runbook 08).

## Notes / Gotchas

- The restic repo retention will eventually prune the agent's snapshots; if you need a permanent
  archive, copy the final snapshot out before it ages off.
