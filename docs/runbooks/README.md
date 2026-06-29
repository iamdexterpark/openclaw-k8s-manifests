# Runbooks

The operational path across the full lifecycle. **Every runbook declares its Target
Environment** in a header block — because the procedure changes with the deployment target.

## The deployment-profile model

This repo is written against a **primary deployment profile** concretely, with room to add others
without rewriting the core. Runbooks are split so each profile is independently followable:

```
runbooks/
├── _common/                  # profile-INDEPENDENT steps (same regardless of target)
│   ├── 01-image-build
│   ├── 05-update-and-rollback
│   └── 07-decommission
├── profile-local-k3s-gcp/    # PRIMARY profile: self-hosted K3s + GCP services
│   ├── 02-provision-cluster
│   ├── 03-platform-bootstrap
│   ├── 04-secrets
│   ├── 06-deploy-workload
│   ├── 08-backup-and-restore
│   └── 09-troubleshooting
└── profile-managed-k8s/      # EXTENSION pattern: GKE/EKS/AKS (add when needed)
    └── README.md
```

- **`_common/`** holds steps identical across targets (build a digest-pinned image, push-to-deploy,
  decommission). Don't duplicate these into profiles.
- **`profile-*`** holds the target-specific path: provisioning the cluster, wiring identity to that
  cloud's secret store, exposure. The numbered sequence interleaves `_common` and profile steps —
  follow them in numeric order across both folders.
- **Adding a target** (e.g. you move from local K3s to GKE, or to AWS): copy
  [`profile-managed-k8s/`](profile-managed-k8s/README.md) as a starting point, implement the
  numbered profile steps for that substrate, reuse `_common/` unchanged. The ADRs and
  [LLD Environment Profiles](../LLD.md#environment-profiles) define what a new profile must specify.

> Everything is sanitized: placeholder registries, addresses, identifiers. Adapt before running.

## Order of operations (primary profile)

| # | Runbook | Folder | What it does |
|---|---|---|---|
| 01 | image-build | `_common` | Build a non-root, digest-pinned image; scan, sign, push. |
| 02 | provision-cluster | `profile-local-k3s-gcp` | Stand up the K3s nodes + base networking. |
| 03 | platform-bootstrap | `profile-local-k3s-gcp` | ESO, ingress/mesh, secret store, backup namespace. |
| 04 | secrets | `profile-local-k3s-gcp` | Seed → GSM → ESO; wire Workload Identity; verify sync. |
| 05 | update-and-rollback | `_common` | Push-to-deploy a change; roll back cleanly. |
| 06 | deploy-workload | `profile-local-k3s-gcp` | Apply overlay → namespace → pod → smoke test. |
| 07 | decommission | `_common` | Final archive, teardown, cloud TTL cleanup. |
| 08 | backup-and-restore | `profile-local-k3s-gcp` | Snapshots to GCS, restore, read the drill. |
| 09 | troubleshooting | `profile-local-k3s-gcp` | Break-fix for this substrate's failure modes. |

## Operating principles

- **Declarative over imperative.** A push/apply changes running state — no out-of-band edits.
- **Pin versions/digests.** A moving tag is a future outage.
- **Least privilege per unit.**
- **A backup nobody has restored is not a backup.** The drill is not optional.
- **Watch the bill.** For agent workloads, spend is an operational signal — see
  [COST-MODEL](../COST-MODEL.md).
