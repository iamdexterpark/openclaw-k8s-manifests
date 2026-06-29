# ADR-0002 — Secrets: external secrets operator + cloud secret manager over Sealed Secrets / Vault Agent

**Status:** Accepted
**Date:** 2026-06-18
**Deciders:** platform owner
**Related:** [HLD §7 Controls](../HLD.md#7-controls-protocols--patterns), [LLD §5](../LLD.md#5-secrets--concrete-wiring)

---

## Context and Problem Statement

Agents need channel tokens, a gateway auth secret, and model API keys. The upstream runtime resolves
secrets from the **host OS keychain** — a host weld we must remove to run on Kubernetes. Two
independent requirements:

1. **A recoverable, in-Git seed** so the whole platform (including the secret backend's bootstrap)
   can be rebuilt from the repo, with secrets auditable/diffable but never plaintext at rest.
2. **A runtime resolution path** that delivers per-agent, least-privilege secrets into pods without
   ever parking a static cloud credential inside the cluster.

## Decision Drivers

- **D1 — No plaintext secret in Git, ever.**
- **D2 — No static, long-lived cloud key sitting in the cluster.**
- **D3 — Per-agent least privilege:** an agent gets only the keys for the channels it's bound to.
- **D4 — Pod stays provider-agnostic:** swapping cloud secret managers must not touch the app or the
  base manifests.
- **D5 — Proportionate ops:** single-operator fleet; avoid a heavy secrets platform if a lighter one
  suffices.
- **D6 — Rebuildable from Git:** disaster recovery can re-bootstrap the secret backend.

## Considered Options

### Option A — Sealed Secrets
Encrypt secrets to a cluster-held key; commit ciphertext to Git; a controller decrypts in-cluster.

- ➕ Satisfies D1 (ciphertext in Git) with minimal moving parts.
- ➖ The cluster's sealing key **is** the authority — no external secret manager, no IAM, no central
  rotation.
- ➖ Rotation is manual and per-secret; no native lease/TTL semantics.
- ➖ Disaster recovery is awkward: lose the controller key, lose every secret (D6 fragile).
- **Verdict: rejected as the runtime source.** (We *do* keep a sealed seed in Git for the bootstrap
  role — the same idea used narrowly, not as the runtime path.)

### Option B — Vault Agent sidecar injection
A secrets platform as authority; a sidecar templates secrets into each pod.

- ➕ Best-in-class dynamic secrets, leasing, fine-grained policy.
- ➖ A **per-pod sidecar** on every agent — material overhead against single-replica edge pods (D5).
- ➖ Requires running and operating the platform (HA, unseal, upgrades) — disproportionate for one
  operator.
- ➖ Couples the pod to that platform's auth/templating model (D4).
- **Verdict: rejected — powerful but over-weight for this fleet.**

### Option C — App calls the cloud secret-manager SDK directly
The runtime fetches its own secrets at boot.

- ➖ Requires a cloud credential in the pod (violates D2) or forking the runtime to add
  workload-identity SDK logic (out of scope — we don't modify the app).
- ➖ Hard-couples the app to one provider (D4).
- **Verdict: rejected.**

### Option D — External Secrets Operator + cloud secret manager via workload identity  ✅
A cluster-wide operator reads from a cloud secret manager using **workload identity** and
materializes a short-lived, namespaced Kubernetes Secret per agent; the pod consumes only that
Secret.

- ➕ No plaintext in Git: only an `ExternalSecret` *reference* (key names) is committed (D1).
- ➕ No static cloud key in-cluster: the operator authenticates via workload identity (D2).
- ➕ Per-agent `ExternalSecret` lists exactly the keys that agent needs (D3).
- ➕ **Pod is provider-agnostic** — it only ever reads a K8s Secret; the provider lives in a single
  `ClusterSecretStore` that the overlay can swap (D4).
- ➕ One operator, no per-pod sidecar (D5).
- ➕ Pairs with a **sealed seed in Git** to bootstrap the secret manager, making the platform
  rebuildable (D6).
- ➖ Adds the operator + a `ClusterSecretStore` to operate; identity misconfig is a failure mode
  (mitigated: the operator surfaces a sync error; the sealed seed is break-glass).
- **Verdict: chosen.**

## Decision

Use the **External Secrets Operator** with a cloud **secret manager** reached via **workload
identity** as the runtime/CI secret source, materializing short-lived namespaced K8s Secrets per
agent. Keep a **sealed seed in Git** strictly for bootstrap/recovery — not for runtime resolution.

Three stores, each doing what it's good at: *Git wants a file → a sealed seed*; *CI wants IAM → the
secret manager*; *pods want a mount → the operator-materialized Secret*.

## Consequences

**Positive**
- Clean separation of recovery seed (Git) from runtime authority (secret manager) from last-mile
  delivery (materialized Secret). Pods never touch the secret manager.
- A provider swap is a `ClusterSecretStore` change; base manifests and the app are untouched.
- Least privilege is expressible per agent and reviewable in the overlay.

**Negative / Risks accepted**
- Operational dependency on the operator + a correct workload-identity binding (HLD risk R3).
  Break-glass via the sealed seed bounds the blast radius.
- A short-lived K8s Secret still exists in etcd at runtime; mitigated by namespace isolation,
  least-privilege RBAC, and (recommended) etcd encryption-at-rest in the overlay.

## Revisit If

- Dynamic/leased secrets (short-TTL DB creds, etc.) become a requirement → reconsider a full secrets
  platform.
- The fleet grows past single-operator into multi-tenant → stronger policy isolation may justify
  heavier tooling.
