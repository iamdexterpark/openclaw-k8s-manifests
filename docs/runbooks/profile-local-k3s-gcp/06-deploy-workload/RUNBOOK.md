# Runbook 06 — Deploy a Workload (Onboard an Agent)

> **Target Environment** (mandatory — a runbook that doesn't declare its env is a trap)
> | | |
> |---|---|
> | **Deployment profile** | `profile-local-k3s-gcp` (primary) |
> | **Substrate** | self-hosted K3s |
> | **Cloud services used** | GCS (state), Google Secret Manager (secrets), Pub/Sub (inbound, optional) |
> | **Identity model** | GCP Workload Identity (KSA ↔ GSA) |
> | **What changes under a different profile** | storage-class + exposure annotations may differ; the overlay itself is the same — see [profile-managed-k8s](../../profile-managed-k8s/README.md) |

**Goal:** bring one new agent online — overlay → namespace → config → secrets → pod → smoke test.
This is the "add an agent by adding an overlay" path (G2).
**Time:** ~10 min · **Risk:** low · **Reversible:** yes (`kubectl delete ns <id>`)

## Prerequisites

- Platform bootstrapped (Runbook 03) and secrets loaded (Runbook 04).
- A pinned image digest (Runbook 01).

## Steps

### 1. Copy the example overlay

```bash
cp -r manifests/overlays/example manifests/overlays/<id>
```

### 2. Set identity

- `kustomization.yaml`: `namespace: <id>`, `namePrefix: <id>-`, pin `images[].digest` (Runbook 01).
- `patch-serviceaccount.yaml`: the GSA in the Workload Identity annotation.
- `patch-config.yaml`: `state_prefix`, and in `openclaw.json` the `id`, `displayName`,
  `defaultModel`, channel bindings. Leave `heartbeat.enabled: false` unless you've sized its token
  floor ([COST-MODEL §3](../../COST-MODEL.md#3-️-runtime-cost-traps-read-before-deploying)).
- `patch-externalsecret.yaml`: the `remoteRef.key` paths to `agents/<id>/…`; add channel-token keys
  **only** for the channels this agent is bound to.

### 3. Validate, then apply

```bash
scripts/validate.sh                                   # build + digest assert + secret scan
kustomize build manifests/overlays/<id> | kubectl apply -f -
kubectl -n <id> rollout status deploy/<id>-workload --timeout=180s
```

## Verification

```bash
kubectl -n <id> get externalsecret,secret,configmap,deploy,svc,networkpolicy,pdb,sa
kubectl -n <id> get externalsecret agent-secrets -o jsonpath='{.status.conditions[0].reason}'  # SecretSynced
kubectl -n <id> port-forward svc/<id>-workload 8080:80 >/dev/null 2>&1 &
curl -sf localhost:8080/healthz && echo "  agent healthy"
```

- Pod `Running`, readiness green; `ExternalSecret` `SecretSynced`; `/healthz` 200 over the Service.
- The agent is **not** reachable from outside the `role: ingress` namespace (NetworkPolicy present).

## Rollback

```bash
kubectl delete ns <id>     # namespace-per-agent: one command removes everything
```

## Notes / Gotchas

- A `Pending` pod with no node is usually resource pressure — the agent is node-agnostic, so any node
  with headroom will take it.
- An `ImagePullBackOff` means the overlay digest doesn't exist in the registry — re-check Runbook 01.
