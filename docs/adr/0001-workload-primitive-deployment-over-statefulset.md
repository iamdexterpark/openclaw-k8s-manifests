# ADR-0001 — Workload primitive: single-replica Deployment over StatefulSet / DaemonSet

**Status:** Accepted
**Date:** 2026-06-18
**Deciders:** platform owner
**Related:** [HLD §6 Architecture](../HLD.md#6-architecture), [ADR-0003 (state transport)](0003-state-transport-object-store-over-pvc.md)

---

## Context and Problem Statement

Each agent is a single-writer runtime (see [HLD §2.3](../HLD.md#23-the-keystone-constraint-single-writer)):
it mutates an append-heavy memory corpus and live transcripts on a filesystem with **no internal
concurrency control**. Two instances writing the same corpus corrupt it. The runtime is long-lived
and stateful in behavior, yet — by deliberate design ([ADR-0003](0003-state-transport-object-store-over-pvc.md)) —
holds **no durable data on the pod**; all state is externalized to object storage.

Which Kubernetes workload primitive correctly expresses *"exactly one pod per agent, on any node,
never two writers at once, owning nothing on disk"*?

## Decision Drivers

- **D1 — Single-writer safety:** the primitive + rollout must make "two live writers for one agent"
  structurally hard, including *during* rollouts.
- **D2 — Stateless pod:** state is external; we do not want a per-pod volume lifecycle.
- **D3 — Substrate-agnostic (G7):** must run identically on edge K3s and managed cloud, with no
  dependency on a storage class or node identity.
- **D4 — Scale by agent, not by replica (G2):** "more agents" = more overlays, not more pods of one
  workload.
- **D5 — Operational simplicity:** least machinery for a single-operator fleet.

## Considered Options

### Option A — DaemonSet
Runs one pod per node.

- ➖ Expresses the wrong cardinality (D4): agent count is unrelated to node count.
- ➖ No per-agent identity; can't map "agent-b" to a pod cleanly.
- ➖ Adding an agent would mean adding a node, or hacking nodeSelectors — absurd for this workload.
- **Verdict: rejected — wrong primitive.**

### Option B — StatefulSet
The reflexive choice for single-writer + stable identity.

- ➕ Gives stable network identity and at-most-one-per-ordinal semantics (helps D1).
- ➕ Ordered, controlled rollout.
- ➖ Its **core value is stable per-replica PVCs** — exactly the volume lifecycle we eliminated (D2).
- ➖ Pulls in headless-Service + node/zone/storage-class coupling that fights D3.
- ➖ We'd adopt a heavier controller to obtain a guarantee (one writer) we already get more cheaply
  with `replicas:1` + `Recreate`, while paying for a feature (sticky volumes) we explicitly don't want.
- **Verdict: rejected — right instinct, wrong fit once state is externalized.**

### Option C — Deployment, `replicas: 1` + `Recreate` + PodDisruptionBudget  ✅
- ➕ With state external, the pod is genuinely stateless — a Deployment is the *honest* model (D2).
- ➕ Single-writer enforced by composition (D1): `replicas: 1` caps the steady-state count;
  `strategy.type: Recreate` terminates the old pod **before** starting the new one — no rolling
  window where two writers overlap (the failure a default `RollingUpdate` would create); a **PDB**
  guards against voluntary disruption, and a `replicas != 1` alert catches accidental drift.
- ➕ Zero storage-class / node-identity coupling (D3).
- ➕ Scaling the fleet is "add an overlay" (D4); no change to this workload's shape.
- ➕ Smallest moving-part count (D5).
- ➖ A Deployment won't *enforce* single-writer by itself — it relies on the
  `Recreate`+`replicas:1`+PDB composition and an alert. Accepted as a managed risk.
- **Verdict: chosen.**

## Decision

Use a **Deployment with `replicas: 1`, `strategy.type: Recreate`, and a PodDisruptionBudget** per
agent. Enforce the single-writer invariant by composition rather than by adopting a StatefulSet.

## Consequences

**Positive**
- Pod is stateless and node-agnostic; a drained node is a non-event (a new pod pulls state from
  object storage). Substrate-agnostic goal preserved.
- Fleet scales horizontally by overlay; the base is untouched.
- Minimal controller surface; easy to reason about and to run on small ARM edge nodes.

**Negative / Risks accepted**
- Single-writer is enforced by configuration discipline, not by the primitive's intrinsic
  guarantees. Mitigated with `Recreate` (no rollout overlap), a PDB, an alert on `replicas != 1`,
  and restore drills that would surface corruption. Tracked as HLD risk **R1**.
- A `Recreate` rollout has a brief availability gap (old pod down before new pod ready). Acceptable:
  agents are not low-latency always-on services, and the gap is bounded by the startup probe.

## Revisit If

- The runtime gains internal write-locking / multi-writer reconciliation → a rolling strategy or
  active-active could become safe.
- A genuine high-churn local cache appears that benefits from a sticky PVC → re-evaluate StatefulSet.
