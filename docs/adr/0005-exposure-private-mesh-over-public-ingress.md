# ADR-0005 — Exposure: private mesh + default-deny over public ingress / LoadBalancer

**Status:** Accepted
**Date:** 2026-06-18
**Deciders:** platform owner
**Related:** [HLD §6 Architecture](../HLD.md#6-architecture), [LLD §6 Networking](../LLD.md#6-networking--concrete)

---

## Context and Problem Statement

Agents are reached by their operator (webchat over a private overlay) and, for some channels, by an
inbound webhook from a third-party messaging provider. Agents also hold **privileged tools** — shell
exec and outbound API access ([HLD §2.1](../HLD.md#21-an-agent-runtime-not-a-stateless-web-service)).
The wrong default — "expose each agent's Service via a public ingress/LoadBalancer" — would put a
tool-wielding runtime on the public internet. How should the fleet be reached?

## Decision Drivers

- **D1 — Minimize public attack surface:** a compromised agent endpoint = remote code execution
  surface.
- **D2 — Operator access from anywhere** (laptop/phone) without exposing agents publicly.
- **D3 — Support inbound channel webhooks** where a provider must POST in.
- **D4 — Per-agent isolation:** reaching agent-a must not imply reaching agent-b.
- **D5 — Substrate-agnostic:** no dependency on a cloud L4/L7 LB; must work on edge K3s too.
- **D6 — Default-deny posture** consistent with the NetworkPolicy model.

## Considered Options

### Option A — Public ingress / LoadBalancer per agent
Each agent Service behind a public-facing ingress or cloud LB.

- ➖ Puts a **privileged, tool-running** agent directly on the internet (D1) — unacceptable default.
- ➖ Per-agent public hostnames widen surface and complicate authn at the edge.
- ➖ A cloud LB per agent is provider-coupled and costly; not edge-portable (D5).
- **Verdict: rejected — wrong threat posture for this workload.**

### Option B — Single shared public ingress, host/path-routed to agents
One ingress fronts all agents.

- ➕ Cheaper than per-agent LBs.
- ➖ Still public; still fronts privileged runtimes (D1).
- ➖ A routing/authn slip exposes every agent at once (D4).
- **Verdict: rejected for general access** — but retained *narrowly* for the unavoidable webhook case.

### Option C — Private mesh overlay + default-deny, with one optional dedicated webhook ingress  ✅
Operator and agents join a private WireGuard-style mesh; webchat travels over the mesh; each agent
gets a **private** per-agent hostname. NetworkPolicy is default-deny. The *only* public surface, if
any, is a single dedicated ingress path for a channel webhook.

- ➕ **No agent is publicly reachable** by default; the operator reaches them over the mesh from any
  device (D1/D2).
- ➕ **Per-agent private hostnames** + default-deny east-west give real isolation (D4/D6).
- ➕ Inbound webhooks handled by **one dedicated, minimal ingress path** — a single small, auditable
  public surface instead of N (D3).
- ➕ Mesh + NetworkPolicy work identically on edge and cloud — no cloud LB dependency (D5).
- ➖ Operator onboarding requires mesh enrollment (key distribution) — a one-time cost.
- ➖ The webhook ingress remains a public surface; kept minimal, single-purpose, and isolated.
- **Verdict: chosen.**

> For the primary profile, the inbound path that would otherwise need a public ingress is handled by
> an **egress-only Pub/Sub pull** instead (the agent pulls events; the provider never connects in) —
> shrinking even the residual webhook surface to zero in the common case. See
> [LLD §6](../LLD.md#6-networking--concrete).

## Decision

Reach the fleet over a **private mesh overlay** with **per-agent private hostnames** and a
**default-deny NetworkPolicy**. Expose **at most one dedicated ingress path** for channel webhooks
that genuinely require inbound public POSTs; prefer an egress-only pull where the channel supports
it. No per-agent public ingress or LoadBalancer.

## Consequences

**Positive**
- Privileged agent runtimes are off the public internet; the public surface is reduced to (at most)
  one purpose-built webhook path, or zero when pull-based ingestion is available.
- Operator access is device-portable via the mesh without weakening posture.
- The exposure model is identical across substrates; no cloud LB lock-in.

**Negative / Risks accepted**
- Mesh enrollment is a prerequisite for access — a deliberate friction that buys a smaller attack
  surface.
- A residual webhook ingress (where used) is a public surface; mitigated by isolating it, scoping it
  to one path, and validating requests at that edge.

## Revisit If

- A use case requires broad public, unauthenticated access to an agent → that agent likely belongs in
  a different, hardened tier, not this fleet.
