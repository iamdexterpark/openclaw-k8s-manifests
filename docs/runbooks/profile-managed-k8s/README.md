# Profile: Managed K8s (GKE / EKS / AKS) — extension stub

This is the **extension pattern**, not a completed profile. The repo's primary profile is
[`profile-local-k3s-gcp`](../profile-local-k3s-gcp). If you decide to push the workload onto a
managed control plane (GKE, EKS, AKS), implement this profile rather than mutating the primary one.

## What a new profile must specify

Per [LLD §Environment Profiles](../../LLD.md#environment-profiles), a deployment profile defines:

| Axis | local-k3s-gcp (primary) | managed-k8s (this stub) |
|---|---|---|
| **Cluster provisioning** | self-host K3s on owned nodes | `gcloud/eksctl/az` creates managed CP + node pool |
| **Identity model** | GCP Workload Identity (KSA↔GSA) | GKE WI / EKS IRSA / AKS Workload Identity |
| **Secret store** | GSM via ESO | same cloud's secret manager via ESO (swap provider block) |
| **State / object store** | GCS | GCS / S3 / Azure Blob |
| **Exposure** | private mesh / egress-only | managed LB / Ingress (mind public surface + cost) |
| **Cost shape** | hardware CapEx + cloud-service OpEx | managed-CP fee + node-hours + LB/egress |

## Runbooks to author for this profile

Reuse `_common/` unchanged (01-image-build, 05-update-and-rollback, 07-decommission). Implement the
profile-specific numbered steps:

- `02-provision-cluster` — create the managed cluster + node pool (declarative: Terraform preferred).
- `03-platform-bootstrap` — ESO + ingress for this cloud.
- `04-secrets` — wire that cloud's secret store + identity binding.
- `06-deploy-workload` — same overlay; confirm storage class / LB annotations differ.
- `08-backup-and-restore` — point the backup at this profile's object store.
- `09-troubleshooting` — this substrate's failure modes (managed-CP quirks, LB, IAM).

> Whichever decisions differ materially from the primary profile (e.g. exposure model, cost
> tradeoff) deserve their own ADR or a supplement to the existing one — don't bury a target switch
> in a runbook.
