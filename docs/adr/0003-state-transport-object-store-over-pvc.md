# ADR-0003 — State transport: versioned object storage over PVC / RWX volume

**Status:** Accepted
**Date:** 2026-06-18
**Deciders:** platform owner
**Related:** [HLD §7 Controls](../HLD.md#7-controls-protocols--patterns), [ADR-0001 (workload primitive)](0001-workload-primitive-deployment-over-statefulset.md), [ADR-0004 (backup)](0004-backup-restic-over-velero.md)

---

## Context and Problem Statement

The agent's durable state is its **memory / retrieval corpus**: curated long-term memory, daily
logs, session transcripts, and media — an **append-heavy collection of mostly-markdown files** (see
[HLD §2.2](../HLD.md#22-the-memory-corpus-is-a-retrieval-substrate-not-some-state)). Upstream, "the
filesystem *is* the database," welding the agent to one host. To run as a fleet where any node can
run any agent, that state must live **off the pod**. How should it be transported and hosted?

## Decision Drivers

- **D1 — Node independence:** a rescheduled pod on any node must recover full state. No detach/attach
  dance.
- **D2 — Substrate-agnostic (G7):** no dependency on a specific CSI driver or storage class.
- **D3 — Single-writer safe ([ADR-0001](0001-workload-primitive-deployment-over-statefulset.md)):**
  the transport must not invite a second concurrent writer.
- **D4 — Point-in-time recovery:** the corpus is the product; we need cheap per-object history +
  snapshot restore.
- **D5 — Shape fit:** the store should match an append-heavy file corpus, not pretend it's a block DB.
- **D6 — Keeps the pod stateless** so [ADR-0001](0001-workload-primitive-deployment-over-statefulset.md)'s
  Deployment model holds.

## Considered Options

### Option A — Per-agent PersistentVolumeClaim (block or filesystem)
Give each agent a sticky PVC; mount it; runtime reads/writes locally.

- ➕ Simplest app change: it's just a filesystem, like upstream.
- ➖ **Re-welds the agent to a node/zone + storage class** (violates D1/D2); a reschedule means
  detach/attach, impossible across zones for many block drivers.
- ➖ Pushes the design back toward a **StatefulSet** (the thing
  [ADR-0001](0001-workload-primitive-deployment-over-statefulset.md) rejected) (D6).
- ➖ Point-in-time recovery depends on CSI volume snapshots — driver-specific, coarse-grained (D4).
- **Verdict: rejected — recreates the host weld in Kubernetes clothing.**

### Option B — Shared ReadWriteMany volume (NFS / CephFS)
One network filesystem all agent pods can mount.

- ➕ Node-independent: any node can mount (helps D1).
- ➖ **RWX + a single-writer app with no file locking** is a corruption trap if isolation ever slips (D3).
- ➖ Operating NFS/Ceph (or paying for managed RWX) is heavy for a single-operator edge fleet.
- ➖ Per-file version history isn't native; PITR still needs a separate backup system (D4).
- **Verdict: rejected — wrong risk/ops profile.**

### Option C — Versioned cloud object storage (sync + snapshots)  ✅
The agent's state directory is synced to a versioned object-store prefix; snapshots layer on top
([ADR-0004](0004-backup-restic-over-velero.md)).

- ➕ **Node-independent** by construction: a new pod pulls its prefix and resumes — a drained node is
  a non-event (D1).
- ➕ **Substrate-agnostic:** object storage exists on every target (edge + cloud); no CSI/storage-class
  coupling (D2).
- ➕ Keeps the pod stateless → Deployment model intact (D3/D6).
- ➕ **Object versioning** gives cheap per-object PITR; the snapshot engine gives whole-corpus restore (D4).
- ➕ **Matches the corpus shape** — many small, append-heavy files map naturally to objects; far
  better fit than a block device pretending to be a database (D5).
- ➖ Object stores are not POSIX and are eventually-consistent-ish; a sync layer (and tolerance for
  brief write-queueing on outage) is required. Accepted (HLD risk R2: serve from scratch, queue
  writes, alert).
- ➖ Sync semantics must respect single-writer — enforced upstream by
  [ADR-0001](0001-workload-primitive-deployment-over-statefulset.md), not by the store.
- **Verdict: chosen.**

## Decision

Externalize all durable agent state to **versioned cloud object storage**, with the pod using only a
transient **`emptyDir` scratch** volume. Layer **snapshots** on top for whole-corpus PITR
([ADR-0004](0004-backup-restic-over-velero.md)). No PersistentVolume on the agent pod.

### How it actually works (the load-bearing detail — do not skip)

The runtime is **filesystem-native**: it reads and writes its workspace/memory to a local directory
(`OPENCLAW_STATE_DIR=/work`, `workspaceRoot=/work/workspace`, …). There is **no env-driven object-store
backend inside the runtime** — setting a `STATE_BACKEND`/`STATE_PREFIX` variable and hoping the process
externalizes state is a **fiction**; those vars are inert. An `emptyDir` mount with no sync therefore
**silently evaporates all agent memory on every pod restart** (and the `Recreate` strategy from
[ADR-0001](0001-workload-primitive-deployment-over-statefulset.md) guarantees a restart on any change).

Durability is an **explicit sync wrapped around the local dir**, not a runtime feature:

- **`initContainer: state-hydrate`** pulls `<object-store>/<STATE_PREFIX>/` → `/work` before the runtime
  starts (a no-op on first-ever boot).
- **`sidecar: state-syncback`** pushes `/work` → the prefix on a short interval (pair with a `preStop`
  flush on the main container for a clean last write).
- The runtime sees an ordinary local directory; the object store is the source of truth across restarts.

This is the difference between "looks durable" and "is durable." See `manifests/base/deployment.yaml`.

## Consequences

**Positive**
- Pod is fully stateless; reschedule/recovery is "pull prefix, resume." Enables the
  [ADR-0001](0001-workload-primitive-deployment-over-statefulset.md) Deployment model and
  substrate-agnostic portability.
- Two recovery interfaces: object versioning (single-object rollback) + snapshot (full set).
- No CSI/storage-class/zone coupling to reason about per cluster.

**Negative / Risks accepted**
- Object-store unavailability blocks durable writes; mitigated by serving from in-memory/scratch and
  queueing writes, with alerting (HLD R2).
- A sync layer sits between the app's filesystem expectations and object semantics — a moving part to
  operate and monitor.
- **The durability lives entirely in the hydrate-init + syncback-sidecar, not in the runtime.** If a
  reader strips those (e.g. "simplify" to a bare emptyDir + the inert `STATE_BACKEND` env), state is
  lost on the next restart with no error. The sync containers are not optional scaffolding; they ARE
  the state model. (This was a real trap caught in implementation — the idealized "the runtime
  externalizes state" design did not match the filesystem-native runtime.)

## Revisit If

- A genuinely high-IOPS, POSIX-locking workload appears for an agent → a scoped local PVC cache (with
  the corpus still authoritative in object storage) could be added.
