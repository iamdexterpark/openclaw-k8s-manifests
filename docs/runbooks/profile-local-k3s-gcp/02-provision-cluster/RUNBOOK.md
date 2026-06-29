# Runbook 02 — Provision the Cluster

> **Target Environment** (mandatory — a runbook that doesn't declare its env is a trap)
> | | |
> |---|---|
> | **Deployment profile** | `profile-local-k3s-gcp` (primary) |
> | **Substrate** | self-hosted K3s on owned ARM nodes |
> | **Cloud services used** | none yet (GCP services wired in runbooks 03–04) |
> | **Identity model** | local node access (SSH); GCP Workload Identity configured in 03–04 |
> | **What changes under a different profile** | on `managed-k8s` this whole runbook becomes "create a managed CP + node pool" (Terraform) — see [profile-managed-k8s](../../profile-managed-k8s/README.md) |

**Goal:** a running, single-cluster K3s control + compute plane on owned hardware, ready for the
platform layer.
**Time:** ~30 min · **Risk:** med · **Reversible:** yes (`k3s-uninstall.sh`)

## Prerequisites

- One or more owned nodes (e.g. ARM mini-PCs) on a private LAN.
- SSH access; a private mesh (WireGuard-style) for operator access ([ADR-0005](../../adr/0005-exposure-private-mesh-over-public-ingress.md)).
- `kubectl` + `kustomize` on your workstation.

## Steps

### 1. Install the K3s controller node

```bash
# On the first (controller) node:
curl -sfL https://get.k3s.io | sh -s - server \
  --disable traefik \
  --node-label role=controller
sudo cat /var/lib/rancher/k3s/server/node-token   # join token for workers
```

### 2. Join worker nodes

```bash
# On each worker node:
curl -sfL https://get.k3s.io | K3S_URL=https://REPLACE_CONTROLLER_IP:6443 \
  K3S_TOKEN=REPLACE_JOIN_TOKEN sh -s - agent --node-label role=worker
```

### 3. Pull the kubeconfig to your workstation

```bash
scp REPLACE_CONTROLLER:/etc/rancher/k3s/k3s.yaml ~/.kube/openclaw-fleet.yaml
# edit server: to the controller's mesh address, then:
export KUBECONFIG=~/.kube/openclaw-fleet.yaml
```

### 4. Label the ingress/mesh namespace

```bash
kubectl create namespace mesh-ingress
kubectl label namespace mesh-ingress role=ingress --overwrite   # NetworkPolicy allows only this ns
```

## Verification

```bash
kubectl get nodes -o wide                 # all nodes Ready, roles labeled
kubectl get ns mesh-ingress -o jsonpath='{.metadata.labels.role}'   # → ingress
```

## Rollback

```bash
# On each node:
/usr/local/bin/k3s-uninstall.sh           # controller
/usr/local/bin/k3s-agent-uninstall.sh     # worker
```

## Notes / Gotchas

- Traefik is disabled because exposure is via the mesh, not a public ingress
  ([ADR-0005](../../adr/0005-exposure-private-mesh-over-public-ingress.md)). Re-enable only if a
  channel genuinely needs a public webhook path.
- K3s ships `local-path` as the default StorageClass; the agent pods use **no PVC**, so it matters
  only for incidental platform components.
