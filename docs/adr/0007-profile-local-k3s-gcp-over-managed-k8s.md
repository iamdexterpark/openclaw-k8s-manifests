# ADR-0007 — Primary deployment profile: self-hosted K3s + cloud services over a managed control plane

**Status:** Accepted
**Date:** 2026-06-18
**Deciders:** platform owner
**Related:** [HLD §10 Portability](../HLD.md#10-portability), [LLD §Environment Profiles](../LLD.md#environment-profiles), [COST-MODEL §1](../COST-MODEL.md#1-infrastructure-plane--substrate-cost)

---

## Context and Problem Statement

The architecture is substrate-agnostic, but a real repo must pick a **primary deployment profile** to
write the LLD, the manifests, and the runbooks against concretely. The fork is genuine: run on a
**self-hosted cluster** (K3s on owned hardware) that consumes **cloud services** for the durable
primitives, or run on a **managed control plane** (GKE/EKS/AKS). Which is the primary target, and on
what grounds — so that the loser is documented and a future switch is a deliberate, ADR-worthy move
rather than a silent drift?

## Decision Drivers

- **D1 — Lowest recurring spend** for a single-operator fleet (the substrate plane; see
  [COST-MODEL §1](../COST-MODEL.md#1-infrastructure-plane--substrate-cost)).
- **D2 — Substrate-agnostic primitives preserved:** the choice must not leak into the base manifests
  or the app.
- **D3 — Operational realism for one operator:** the labor cost of running it must be acceptable to a
  team of one.
- **D4 — Owns the durable primitives reliably:** state, secrets, inbound events must be production-grade
  even if the cluster isn't a managed one.
- **D5 — A clean upgrade path** to a managed control plane if scale or team size demands it.

## Considered Options

### Option A — Fully managed control plane (GKE / EKS / AKS)
The provider runs the control plane, upgrades, and HA.

- ➕ **Lower operational labor** (D3): no control-plane upkeep, managed node pools, built-in HA.
- ➕ Cloud-native identity and secret stores are first-class.
- ➖ **~$72/mo per cluster control-plane fee before a single node-hour** (D1) — for a single-operator
  fleet where the substrate should be a rounding error, that's the *largest* line item.
- ➖ Node-hours are always-on OpEx; LBs and egress add up.
- **Verdict: rejected as primary — right for scale/teams, wrong for a one-operator edge fleet's
  economics. Retained as the `managed-k8s` extension profile.**

### Option B — Fully self-hosted (cluster *and* state/secrets/events on owned hardware)
Run everything — including object storage, a secret manager, and an event bus — on-prem.

- ➕ Zero cloud bill.
- ➖ You now operate object storage, a secret manager, and a message bus yourself — **the labor
  explodes** (D3) and the durable primitives become as fragile as the hardware (D4).
- ➖ Re-welds durability to one site; defeats the node-independence the whole design is for.
- **Verdict: rejected — saves dollars, spends reliability and time we don't have.**

### Option C — Hybrid: self-hosted K3s + cloud services (`local-k3s-gcp`)  ✅
K3s on owned hardware for the control/compute plane; GCP for the durable primitives — GCS for state +
backups, Secret Manager for credentials, Pub/Sub for egress-only inbound event pull.

- ➕ **No control-plane fee, no node-hours** — the control plane runs free on owned hardware (D1);
  the cloud bill is a handful of metered services that mostly sit inside free tiers
  ([COST-MODEL §1](../COST-MODEL.md#1-infrastructure-plane--substrate-cost)).
- ➕ The **durable primitives are production-grade managed services** (D4) without operating them
  yourself — the reliability that matters is bought, the iron that's cheap is owned.
- ➕ The choice is confined to a `ClusterSecretStore` provider block, the cluster-provisioning
  runbook, and storage-class/exposure annotations — **the base manifests, image, and app are
  untouched** (D2).
- ➕ Pub/Sub egress-only pull means inbound events arrive **behind NAT/CGNAT with no public ingress** —
  the operator's home/edge network needs no inbound port (ties to
  [ADR-0005](0005-exposure-private-mesh-over-public-ingress.md)).
- ➕ Switching to managed later is the `managed-k8s` profile: same base, swap the provider block and
  the provisioning runbook (D5).
- ➖ **You are the SRE** for the control plane and nodes (D3) — OS/firmware/K3s upgrades are yours.
  Accepted: for one operator at this scale the labor is bounded and the savings are large.
- ➖ A residential/business uplink is a single point of failure for cloud-service reachability.
  Mitigated by the queue-and-serve-from-scratch posture (HLD R2).
- **Verdict: chosen.**

## Decision

Adopt **`local-k3s-gcp`** as the primary deployment profile: self-hosted K3s for control/compute,
GCP for the durable primitives (GCS state + backups, Secret Manager, Pub/Sub egress-only inbound).
Keep **`managed-k8s`** as a documented extension profile. A material switch of primary profile —
exposure model, identity model, or cost shape — earns its own ADR (or supersedes this one).

## Consequences

**Positive**
- The substrate plane collapses to ≈ $7–10/mo (electricity-dominated); model inference becomes the
  only spend worth managing.
- Durable primitives are reliable managed services without the operator running them.
- The architecture's substrate-agnosticism is *proven*, not asserted: the profile boundary is small
  and explicit.

**Negative / Risks accepted**
- Control-plane and node operations are the operator's job; mitigated by K3s's small footprint and
  declarative, runbook-driven upgrades.
- Cloud-service reachability depends on the local uplink; mitigated by write-queueing + alerting.

## Revisit If

- The fleet grows past a single operator, or an SLA requires managed HA → promote `managed-k8s` to
  primary (a new ADR).
- A site needs full air-gap / data-residency that forbids cloud services → reconsider a self-hosted
  durable tier despite its labor cost.
