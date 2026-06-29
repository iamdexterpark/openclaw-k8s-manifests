# Runbook 09 — Troubleshooting

> **Target Environment** (mandatory — a runbook that doesn't declare its env is a trap)
> | | |
> |---|---|
> | **Deployment profile** | `profile-local-k3s-gcp` (primary) |
> | **Substrate** | self-hosted K3s |
> | **Cloud services used** | GCS, Google Secret Manager, Pub/Sub |
> | **Identity model** | GCP Workload Identity |
> | **What changes under a different profile** | managed-CP quirks, cloud LB / IAM specifics replace the K3s/WI items below |

**Goal:** break-fix for this substrate's failure modes, mapped to the
[LLD failure-modes table](../../LLD.md#10-failure-modes) and the
[HLD risk register](../../HLD.md#12-risks--open-questions).
**Time:** varies · **Risk:** med · **Reversible:** depends on action

## Symptom → diagnosis → fix

### Two pods for one agent (corruption risk — HLD R1)

```bash
kubectl -n <id> get pods -l app=workload          # should be exactly 1
kubectl -n <id> get deploy/<id>-workload -o jsonpath='{.spec.replicas}{"\n"}{.spec.strategy.type}'
```
Fix: ensure `replicas: 1` and `strategy: Recreate`; the PDB (`maxUnavailable: 0`) should have
prevented this. Re-apply the overlay (Runbook 05). Investigate any manual `kubectl scale`.

### `ExternalSecret` won't sync (HLD R3)

```bash
kubectl -n <id> get externalsecret agent-secrets -o jsonpath='{.status.conditions}'
kubectl -n platform logs deploy/external-secrets | tail
```
Fix: almost always the Workload Identity binding (Runbook 04) or a wrong `remoteRef.key`. Break-glass:
materialize from the sops/age seed.

### `state sync error` in pod logs (HLD R2)

The pod serves from scratch and queues writes — the corpus stays consistent. Check GCS reachability
(egress, local uplink). Confirm the NetworkPolicy allows `:443` egress. When GCS returns, queued
writes flush.

### `ImagePullBackOff`

```bash
kubectl -n <id> describe pod -l app=workload | grep -A2 Events
```
The overlay digest doesn't exist in the registry, or registry auth failed. Re-check Runbook 01;
roll the overlay back to the prior digest if needed (Runbook 05).

### Node drained / lost

Expected behavior, not an incident: the pod is stateless, so it reschedules onto another node and
pulls its state. If it stays `Pending`, it's resource pressure — free headroom or add a node.

### Runaway spend (HLD R7)

```bash
# inspect per-turn token logs; find the offending agent/behavior
```
Fix: disable any heartbeat/poll (`heartbeat.enabled: false`), cap retries, lower reasoning effort.
See [COST-MODEL §3](../../COST-MODEL.md#3-️-runtime-cost-traps-read-before-deploying) and
[OPERATIONS — spend](../../OPERATIONS.md#day-2--operate-run-it-like-it-matters).

## Verification

After any fix:

```bash
kubectl -n <id> rollout status deploy/<id>-workload
kubectl -n <id> port-forward svc/<id>-workload 8080:80 >/dev/null 2>&1 &
curl -sf localhost:8080/healthz && echo "  healthy"
```

## Rollback

Every fix above is a declarative change (re-apply / Git revert) or a benign read. Nothing here edits
live state out of band.

## Notes / Gotchas

- When in doubt, the safe primitive is: scale the writer to **0**, restore from a known-good snapshot
  (Runbook 08), scale to **1**. State lives in GCS, so this is cheap and corruption-proof.
