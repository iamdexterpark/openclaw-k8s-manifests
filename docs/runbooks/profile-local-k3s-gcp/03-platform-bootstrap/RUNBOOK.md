# Runbook 03 — Platform Bootstrap

> **Target Environment** (mandatory — a runbook that doesn't declare its env is a trap)
> | | |
> |---|---|
> | **Deployment profile** | `profile-local-k3s-gcp` (primary) |
> | **Substrate** | self-hosted K3s (from Runbook 02) |
> | **Cloud services used** | Google Secret Manager (via ESO), GCS (backup target) |
> | **Identity model** | GCP Workload Identity (KSA ↔ GSA) |
> | **What changes under a different profile** | the ESO provider block + the WI binding mechanism (GKE WI / IRSA / AKS WI) — see [profile-managed-k8s](../../profile-managed-k8s/README.md) |

**Goal:** stand up the cluster-scoped primitives every agent depends on — the secret operator, the
secret store, and the backup CronJobs — before any agent is deployed.
**Time:** ~20 min · **Risk:** med · **Reversible:** yes

## Prerequisites

- A running cluster (Runbook 02), `KUBECONFIG` set.
- A GCP project with Secret Manager + a versioned GCS bucket created.
- Workload Identity available for the cluster (for self-hosted K3s, a WI federation / GSA-key-free
  binding mechanism configured).

## Steps

### 1. Install the External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace platform --create-namespace --set installCRDs=true
```

### 2. Apply the platform layer (secret store + backup CronJobs)

```bash
kustomize build manifests/platform | kubectl apply -f -
```

Replace the `REPLACE_PROJECT_ID` / `REPLACE_REGION` / `REPLACE_CLUSTER` placeholders in
[`clustersecretstore.yaml`](../../../manifests/platform/external-secrets/clustersecretstore.yaml)
first.

### 3. Confirm the secret store is valid

```bash
kubectl -n platform get clustersecretstore cloud-secret-manager -o wide   # STATUS: Valid
```

## Verification

```bash
kubectl -n platform get pods                          # external-secrets running
kubectl -n platform get clustersecretstore            # cloud-secret-manager: Valid
kubectl -n platform get cronjob state-backup restore-drill   # both scheduled
```

## Rollback

```bash
kustomize build manifests/platform | kubectl delete -f -
helm uninstall external-secrets -n platform
```

## Notes / Gotchas

- A `ClusterSecretStore` status of `InvalidProviderConfig` almost always means the Workload Identity
  binding is wrong — fix it in Runbook 04 before deploying any agent.
