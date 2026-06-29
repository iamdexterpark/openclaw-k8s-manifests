# Runbook 05 — Update & Rollback

> **Target Environment** (mandatory — a runbook that doesn't declare its env is a trap)
> | | |
> |---|---|
> | **Deployment profile** | `_common` — profile-independent |
> | **Substrate** | any K8s cluster reachable by `kubectl`/`kustomize` |
> | **Cloud services used** | none directly (GitOps reconcile) |
> | **Identity model** | your cluster credential / CI deploy identity |
> | **What changes under a different profile** | nothing — push-to-deploy is identical across targets |

**Goal:** change a running agent (persona, config, or image) safely via push-to-deploy, and roll back
cleanly when needed.
**Time:** ~5 min · **Risk:** low/med · **Reversible:** yes (Git revert)

## Principle

A push is the **only** way to change a running agent. No `kubectl edit` on live resources — the next
apply (or a reconciler) reverts it and you lose the change silently. Config immutability
([ADR-0006](../../adr/0006-config-immutability-read-only-over-writable.md)) makes this structural.

## Update (the normal path)

### 1. Make the change in Git

- persona/config edit → under the agent's `persona/` or the overlay's `patch-config.yaml`
- image bump → update the `digest` in the overlay `kustomization.yaml` (from Runbook 01)

### 2. Open a PR — gates run automatically

```bash
scripts/validate.sh   # reproduce CI locally first
```

- `validate`: preflight, doc-sync, `kustomize build` all kustomizations, `@sha256` assertion, secret
  scan.
- `render-and-diff`: posts the **cluster-level** diff (what actually changes), not just the source diff.

### 3. Merge → reconcile

```bash
kustomize build manifests/overlays/<id> | kubectl apply --server-side -f -
kubectl -n <id> rollout status deploy/<id>-workload --timeout=180s
```

The `Recreate` strategy terminates the old pod before the new one starts — never two writers
([ADR-0001](../../adr/0001-workload-primitive-deployment-over-statefulset.md)).

## Verification

```bash
kubectl -n <id> get deploy/<id>-workload -o jsonpath='{.spec.template.spec.containers[0].image}'  # new digest
kubectl -n <id> rollout status deploy/<id>-workload                                                # complete
```

## Rollback

```bash
git revert <commit>          # config/persona/digest all roll back via Git
git push                     # CI re-applies the prior state
# or, immediate:
kubectl -n <id> rollout undo deploy/<id>-workload
```

State rolls back independently: object versioning restores a single object; restic restores the
whole corpus (Runbook 08).

## Notes / Gotchas

- A bad config schema is caught at the `validate` gate — the merge is blocked and the **running pod is
  unaffected** because nothing was applied.
