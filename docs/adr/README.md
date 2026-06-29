# Architecture Decision Records

These ADRs capture the **load-bearing decisions** behind this repo. The point of an ADR is
not to document the chosen answer — the deliverable already does that — but to record the
**alternatives that were genuinely on the table** and *why they lost*, so the design can be
audited and revisited as conditions change.

Format: lightly-adapted [MADR](https://adr.github.io/madr/). Each record is self-contained:
context → decision drivers → options considered → decision → consequences → revisit-if.
Start from [`0000-template.md`](0000-template.md).

| ADR | Status | Decision |
|---|---|---|
| [0001](0001-workload-primitive-deployment-over-statefulset.md) | Accepted | Workload primitive: single-replica `Deployment` + `Recreate` + PDB over StatefulSet / DaemonSet. |
| [0002](0002-secrets-external-operator-over-sealed-vault.md) | Accepted | Secrets: external secrets operator + cloud secret manager (via workload identity) over Sealed Secrets / Vault Agent. |
| [0003](0003-state-transport-object-store-over-pvc.md) | Accepted | State transport: versioned cloud object storage over per-agent PVC / RWX volume. |
| [0004](0004-backup-restic-over-velero.md) | Accepted | Backup engine: client-encrypted restic CronJob over Velero / CSI snapshots. |
| [0005](0005-exposure-private-mesh-over-public-ingress.md) | Accepted | Exposure: private mesh + default-deny over public ingress / LoadBalancer. |
| [0006](0006-config-immutability-read-only-over-writable.md) | Accepted | Config immutability: read-only mounts + immutable-config mode over writable config. |
| [0007](0007-profile-local-k3s-gcp-over-managed-k8s.md) | Accepted | Primary profile: self-hosted K3s + cloud services over a managed control plane. |

> All identifiers, providers, and hostnames referenced in these records are placeholders,
> consistent with the rest of this sanitized repo.
