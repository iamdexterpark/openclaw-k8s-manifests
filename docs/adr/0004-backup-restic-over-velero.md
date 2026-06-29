# ADR-0004 — Backup engine: client-encrypted restic over Velero / CSI snapshots

**Status:** Accepted
**Date:** 2026-06-18
**Deciders:** platform owner
**Related:** [HLD §9 Backup, Recovery & Operations](../HLD.md#9-backup-recovery--operations), [LLD §7](../LLD.md#7-backup--restore--concrete-commands), [ADR-0003 (state transport)](0003-state-transport-object-store-over-pvc.md)

---

## Context and Problem Statement

The agent's memory/retrieval corpus is the product
([HLD §2.2](../HLD.md#22-the-memory-corpus-is-a-retrieval-substrate-not-some-state)). It lives in
versioned object storage ([ADR-0003](0003-state-transport-object-store-over-pvc.md)), which gives
per-object rollback — but not whole-corpus, point-in-time, *verified* snapshots. We need a backup
engine that provides consistent snapshots, encryption the storage provider can't read,
retention/pruning, and a **restore path that is proven, not assumed.**

## Decision Drivers

- **D1 — Snapshot the corpus, not a volume:** state is files in object storage, not a PVC.
- **D2 — Client-side encryption:** the bucket must never see plaintext memory/transcripts.
- **D3 — Retention + prune** built in (hourly/daily/weekly).
- **D4 — Substrate-agnostic:** must work on edge K3s with no CSI snapshot support, identically to cloud.
- **D5 — Proven restore:** integrity check + real restore + smoke test on a schedule.
- **D6 — Light footprint:** a CronJob, not a platform.

## Considered Options

### Option A — Velero
The standard Kubernetes backup tool (cluster resources + PV data via CSI or a file-backup plugin).

- ➕ Great at backing up **cluster object state** (namespaces, manifests) and PV-backed apps.
- ➖ Our durable state is **not on a PV** — it's already in object storage
  ([ADR-0003](0003-state-transport-object-store-over-pvc.md)). Velero's PV-snapshot core is aimed at
  a problem we don't have (D1).
- ➖ The K8s objects themselves are **already reconstructable from Git** (GitOps) — backing them up
  is low marginal value here.
- ➖ Heavier to operate than a single CronJob for a single-operator fleet (D6).
- **Verdict: rejected — solves cluster-resource/PV backup, which GitOps + object-store already cover.**

### Option B — CSI volume snapshots
Driver-native snapshots of a PVC.

- ➖ Presupposes a PVC, which this design doesn't use
  ([ADR-0003](0003-state-transport-object-store-over-pvc.md)) (D1).
- ➖ **Driver-specific** — not available/uniform on edge K3s; breaks substrate-agnosticism (D4).
- ➖ Snapshot encryption + cross-provider portability are not guaranteed (D2).
- **Verdict: rejected — wrong layer, not portable.**

### Option C — Client-encrypted restic CronJob  ✅
A CronJob runs `restic backup` of the synced state mirror to an object-store-backed repo.

- ➕ **File/corpus-oriented**, not volume-oriented — matches the append-heavy markdown corpus (D1).
- ➕ **Client-side encryption** is intrinsic: the repo is encrypted before transit; the bucket only
  ever holds ciphertext (D2).
- ➕ Native **retention/prune**: `--keep-hourly 24 --keep-daily 7 --keep-weekly 4 --prune` (D3).
- ➕ Depends only on object storage — **identical on edge and cloud**, no CSI (D4).
- ➕ A weekly **restore-drill CronJob** runs an integrity check, restores `latest`, and smoke-tests a
  throwaway agent — recovery is *verified*, not assumed (D5).
- ➕ Two CronJobs total; trivial to operate (D6).
- ➖ Doesn't back up arbitrary cluster resources — acceptable, because those come from Git (GitOps).
- ➖ restic is a separate tool to learn/operate vs. an all-in-one platform. Low cost for the payoff.
- **Verdict: chosen.**

## Decision

Use **client-side-encrypted restic** in an hourly backup **CronJob** targeting object storage, plus a
**weekly restore-drill CronJob** (integrity check + real restore + smoke test). Do **not** adopt
Velero or CSI snapshots; cluster-resource recovery is delegated to GitOps, and per-object PITR to
object versioning ([ADR-0003](0003-state-transport-object-store-over-pvc.md)).

## Consequences

**Positive**
- Encryption-at-source: a provider compromise doesn't expose memory/transcripts.
- Recovery is continuously verified — backups that fail to restore are caught weekly, not during an
  incident (HLD risk R6).
- Three complementary recovery interfaces: object versioning (one object), restic (whole corpus),
  Git (cluster shape).

**Negative / Risks accepted**
- Cluster-resource backup is *not* this engine's job; it depends on GitOps being the source of truth.
  If a resource isn't in Git, it isn't recoverable here — enforced by the declarative discipline.
- The restic repo password is itself a secret (materialized by the operator); its loss forfeits the
  backups. Treated as a top-tier secret.

## Revisit If

- We start backing up substantial non-Git cluster state (operators with in-cluster state, etc.) →
  Velero becomes worth its weight as a complement, not a replacement.
