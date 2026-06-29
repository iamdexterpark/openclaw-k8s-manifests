# Runbook {{NN}} — {{Title}}

> **Target Environment** (mandatory — a runbook that doesn't declare its env is a trap)
> | | |
> |---|---|
> | **Deployment profile** | {{`_common` (profile-independent) \| `profile-local-k3s-gcp` \| `profile-managed-k8s`}} |
> | **Substrate** | {{e.g. self-hosted K3s on owned ARM nodes \| GKE/EKS/AKS}} |
> | **Cloud services used** | {{e.g. GCS (state), GSM (secrets), Pub/Sub (events) \| none}} |
> | **Identity model** | {{e.g. GCP Workload Identity (KSA↔GSA) \| IRSA \| static (dev only)}} |
> | **What changes under a different profile** | {{the 1–2 steps that differ, + pointer to that profile's runbook}} |

**Goal:** one sentence — what state this runbook leaves you in.
**Time:** ~{{N}} min · **Risk:** low/med/high · **Reversible:** yes/no (see Rollback)

## Prerequisites

- …

## Steps

### 1. {{step}}
```bash
# copy-pasteable, sanitized; placeholders explicit (REPLACE_*)
```

## Verification

How you *know* it worked — the explicit check, expected output, success criterion.

```bash
```

## Rollback

How to undo, cleanly.

```bash
```

## Notes / Gotchas

- …
