# ADR-0006 — Config immutability: read-only mounts + immutable-config mode over writable config

**Status:** Accepted
**Date:** 2026-06-18
**Deciders:** platform owner
**Related:** [HLD §7 Controls](../HLD.md#7-controls-protocols--patterns), [LLD §1 Container Image](../LLD.md#1-component-inventory--versions), [LLD §4 Configuration](../LLD.md#4-configuration--concrete)

---

## Context and Problem Statement

The runtime normally lets an operator mutate config and persona **at runtime** (e.g. a `configure`
command, dynamic onboarding APIs writing into the workspace). In a GitOps fleet, *Git is the only
source of truth*: a running pod that can rewrite its own config creates **drift** — the live state
diverges from the repo, breaking reproducibility, audit, and rollback. How do we guarantee the pod's
configuration equals what's in Git?

## Decision Drivers

- **D1 — No config drift:** the running config must always equal the committed config.
- **D2 — Single change path:** all config/persona changes go through Git → CI → rollout.
- **D3 — Auditability & rollback:** every change is a reviewable commit, revertable by Git.
- **D4 — Defense in depth:** isolate a compromised/buggy agent from rewriting its own guardrails.
- **D5 — Minimal app modification:** prefer the runtime's own supported mechanisms over forking it.

## Considered Options

### Option A — Writable config, reconcile/correct drift after the fact
Let the pod write config; periodically detect and revert divergence.

- ➖ Drift is *possible by construction*; we only catch it afterward (fails D1).
- ➖ A loop that overwrites live changes races with the runtime and is operationally noisy.
- ➖ Doesn't stop a compromised agent from rewriting persona/guardrails between reconciles (D4).
- **Verdict: rejected — detect-and-correct is strictly weaker than prevent.**

### Option B — Read-only mount only (no runtime flag)
Project config via a read-only ConfigMap; rely solely on the mount being RO.

- ➕ Prevents writes to the mounted path (helps D1).
- ➖ The runtime may still attempt config writes elsewhere (a writable `$HOME`, temp, alternate
  paths) or fail confusingly when its own write APIs hit a RO filesystem.
- ➖ Leaves the runtime's mutate-config code paths *enabled*, just thwarted by the FS — fragile (D2).
- **Verdict: insufficient alone — necessary but not sufficient.**

### Option C — Read-only projected ConfigMap **+** the runtime's immutable-config mode  ✅
Project config/persona as a **read-only** ConfigMap *and* run the container with the runtime's own
**immutable-config mode** exported (`OPENCLAW_NIX_MODE=1`), which makes the runtime refuse in-pod
config mutation and direct all changes to the declarative path.

- ➕ **Belt-and-suspenders** (D4): the filesystem is RO *and* the app won't even attempt to mutate —
  it raises a schema/permission error instead of silently diverging.
- ➕ Uses the runtime's **own supported flag** — no fork, no patching (D5).
- ➕ Guarantees the only way to change a running agent is a Git commit → CI → rollout (D1/D2).
- ➕ Every change is a commit: reviewable, diffable, revertable (D3).
- ➖ Loses in-pod convenience mutation — intentional; that's the whole point.
- ➖ Requires config changes to round-trip through CI even for trivial edits — accepted cost of
  determinism.
- **Verdict: chosen.**

## Decision

Project all config and persona files as **read-only** ConfigMaps **and** export the runtime's
**immutable-config mode** (`OPENCLAW_NIX_MODE=1`) in the container. The runtime treats its config
filesystem as immutable and rejects in-pod mutation; **the only path to change a running agent is a
Git commit.**

## Consequences

**Positive**
- Live config provably equals committed config; there is no drift class to chase.
- Strong audit/rollback story: config history *is* Git history; rollback is `git revert`.
- Defense in depth: a misbehaving agent cannot quietly rewrite its own persona/guardrails.

**Negative / Risks accepted**
- No fast in-pod tweaks; every change — even a one-line persona edit — goes through PR + rollout. The
  intended trade: determinism over convenience.
- Depends on the runtime honoring its immutable-config mode; the read-only mount is the backstop if
  it doesn't.

## Revisit If

- The runtime introduces a sanctioned, audited runtime-config API that emits Git-trackable change
  events → a controlled writable path could be reconsidered without sacrificing D1–D3.
