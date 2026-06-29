# OpenClaw on Kubernetes — Cost Model

The story here is simple, and it is the reason this whole repo exists: **for an AI-agent fleet,
the substrate is rarely the expensive part — the model is.** A team that obsesses over node
sizing and never instruments token spend will be surprised by the bill, and the surprise will not
come from compute. So we keep two cost planes deliberately separate, because they behave nothing
alike:

1. **Infrastructure plane** — what it costs to *run the substrate*: compute, storage, network,
   the control plane.
2. **Runtime / intelligence plane** — what it costs to *run the agents*: model inference, and the
   operational traps that quietly multiply it.

Every figure below carries a `Source` (vendor pricing URL + access date) or a stated assumption.
Unsourced numbers are a draft, not a deliverable. Pricing was checked **2026-06-18**; vendors move
prices, so treat the cells as a method, not a quote.

---

## 1. Infrastructure Plane — Substrate Cost

The first decision is the substrate, and it is a genuine fork — not a foregone conclusion. We make
the local-vs-managed tradeoff explicit rather than assume one (see
[deployment profiles](LLD.md#environment-profiles)).

| Cost class | Local cluster (self-hosted K3s on owned hardware) | Cloud-managed K8s (GKE / EKS / AKS) |
|---|---|---|
| **Control plane** | $0 — the controller runs on your own nodes | ~$0.10/hr/cluster ≈ **$72/mo** managed-CP fee |
| **Compute (nodes)** | CapEx: owned hardware, amortized; ~$0 marginal | OpEx: per-node-hour, always-on |
| **Power / cooling** | metered electricity (W × $/kWh × 24 × 30) | included in node price |
| **Object storage** | cloud object store for state + backups | cloud object store + provisioned PVs |
| **Egress / network** | business line (flat) + cloud API egress | inter-AZ + internet egress, metered per GB |
| **Managed add-ons** | self-run — your time is the cost | managed LBs, NAT GW, logging (each billed) |
| **Operational labor** | **higher** — you are the SRE | **lower** — provider owns CP, upgrades, HA |

> **Source — managed control-plane fee:** GKE charges $0.10/hr per cluster regardless of mode/size;
> Google grants $74.40/mo in free credits covering one zonal/Autopilot cluster, after which the fee
> applies. [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing) (accessed 2026-06-18).
> EKS and AKS have comparable per-cluster control-plane fees.

**The hybrid is the cheapest viable shape — and it's this repo's default profile.** A *local*
cluster that consumes *cloud services* (object storage for state, a managed secret store, Pub/Sub
for inbound events) pays cloud OpEx only for those line items — no control-plane fee, no node-hours.
The control plane runs free on hardware we already own; the cloud bill is a handful of metered
services that, at single-operator fleet scale, mostly live inside free tiers.

| Line item (hybrid: local K3s + GCP services) | Unit | Est. monthly | Source / assumption |
|---|---|---|---|
| Object storage — state + restic repo | GB-mo | ~**$0.20** for 10 GB | $0.020/GB-mo Standard, US region. [GCS pricing](https://cloud.google.com/storage/pricing) (2026-06-18) |
| Object storage — Class A/B operations | per 1K ops | **~$0** | hourly backup + state sync ≪ free/low-op tier; assume < $0.50/mo |
| Secret Manager — active versions | per version-mo | **~$0** | first 6 versions free, then $0.06/version-mo; a small fleet stays near free. [GSM pricing](https://cloud.google.com/secret-manager/pricing) (2026-06-18) |
| Secret Manager — access operations | per 10K ops | **~$0** | first 10K access ops/mo free; ESO refresh hourly ≪ 10K. [GSM pricing](https://cloud.google.com/secret-manager/pricing) (2026-06-18) |
| Pub/Sub — inbound message pull | per TiB | **~$0** | first 10 GiB/mo free; chat volume ≪ that. [Pub/Sub pricing](https://cloud.google.com/pubsub/pricing) (2026-06-18) |
| Cloud API egress | per GB | **assumption: < $1/mo** | small JSON payloads; state/backups are inbound writes (free). State as assumption pending real telemetry |
| Electricity — local nodes | kWh | **state per site** | e.g. 3 × 15 W ARM nodes ≈ 32 kWh/mo; at $0.20/kWh ≈ **$6.50/mo**. Assumption — fill with your tariff |
| **Infra subtotal (hybrid)** | | **≈ $7–10/mo** | dominated by electricity; cloud services near free at this scale |

The honest comparison: a managed cluster for the same fleet starts at **~$72/mo just for the
control plane** before a single node-hour. The hybrid trades that recurring fee for owned hardware
(sunk CapEx) plus your time as the operator — see [ADR-0007](adr/0007-profile-local-k3s-gcp-over-managed-k8s.md).

---

## 2. Runtime / Intelligence Plane — Model Cost

This plane is unique to agent workloads and is **the line item most likely to surprise you.** An
idle-looking fleet can burn money continuously if it polls, heartbeats, or reasons on a timer.
Size it deliberately, per agent role.

### 2.1 Hosted frontier models (the big three)

Per-token inference is the default cost driver. The lever is **routing**: a cheap model for
high-volume routing/triage, a frontier model reserved for genuinely hard reasoning.

| Provider / tier | $ / 1M input | $ / 1M output | Best fit | Source (accessed 2026-06-18) |
|---|---|---|---|---|
| Anthropic — Opus (frontier) | $5.00 | $25.00 | hard reasoning, low volume | [Anthropic pricing](https://www.anthropic.com/pricing) |
| Anthropic — Haiku (cheap) | $1.00 | $5.00 | high-volume routing/triage | [Anthropic pricing](https://www.anthropic.com/pricing) |
| OpenAI — GPT-4o mini | $0.15 | $0.60 | cheap general / tools | [OpenAI pricing](https://openai.com/api/pricing/) |
| Google — Gemini 2.5 Pro | $1.25 | $10.00 | long-context reasoning | [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing) |
| Google — Gemini 2.5 Flash | $0.30 | $2.50 | cheap bulk / long-context | [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing) |

> These are list prices as published on the dates above; figures move and tiers are renamed often.
> Re-verify before committing a budget. Batch/cached tiers (typically ~50% off) lower bulk costs
> further where latency is tolerable.

**Monthly model spend (per agent)** = `turns/day × 30 × (avg_input_tok × in_price + avg_output_tok × out_price)`.
The turn-volume assumption dominates the result, so we state it explicitly:

| Agent role | Model tier | Turns/day (assumed) | Avg tok in/out | Est. $/mo | Notes |
|---|---|---|---|---|---|
| Routing / triage | Haiku | 200 | 4,000 / 500 | **≈ $63** | `200×30×(4000×$1/1e6 + 500×$5/1e6)` = `6000×(0.004+0.0025)` |
| General assistant | GPT-4o mini | 100 | 6,000 / 1,500 | **≈ $14** | `100×30×(6000×$0.15/1e6 + 1500×$0.60/1e6)` |
| Hard reasoning | Opus | 20 | 12,000 / 3,000 | **≈ $81** | `20×30×(12000×$5/1e6 + 3000×$25/1e6)` = `600×(0.06+0.075)` |

> The point of the table is not the exact dollar — it's that **the frontier-reasoning agent at
> 1/10th the turn volume still costs more than the cheap agent at full volume.** Routing is the
> lever; reasoning effort is the multiplier.

### 2.2 Subscription vs metered

Some providers sell flat subscription seats. For a programmatic fleet, **metered API billing is
usually the right call** — you pay for actual turns, not seats, and a seat sits idle when an agent
is quiet. One caution that is easy to miss: a subscription seat is **not** an API license. Some
consumer/Pro plans' ToS *prohibit programmatic or automated use*; running a fleet against them is a
compliance and reliability risk, not a cost saving. Read the ToS before wiring a subscription into a
pod.

### 2.3 Local / self-hosted models

Local models (e.g. via Ollama on the cluster's own hardware) trade per-token OpEx for fixed
hardware + power. They amortize favorably **only above a usage threshold**; below it, hosted APIs
are cheaper, full stop.

| Factor | Hosted API | Local model |
|---|---|---|
| Marginal cost / turn | per-token (scales with use) | ~$0 (power only) |
| Fixed cost | $0 | hardware CapEx + idle power |
| Capability ceiling | frontier | bounded by local VRAM / parameter count |
| Crossover | — | where `monthly_tokens × hosted_$/tok > amortized_hardware + power` |

**Worked crossover (assumption):** a cheap-tier hosted turn of ~4,500 tokens costs roughly
`$0.0065` (the Haiku routing turn above). A local node amortized + powered at ~$15/mo breaks even at
**~2,300 such turns/month** — below that, hosted wins; above it, local wins. State your own numbers;
the method is what matters.

**Recommended posture:** route cheap/bulk/low-stakes turns to a local or cheap-tier model; reserve
frontier hosted models for genuinely hard reasoning. Make the routing explicit per agent role —
it's the single biggest lever on this plane.

---

## 3. ⚠️ Runtime Cost Traps (read before deploying)

These are operational footguns that turn a "cheap" fleet into a steady bleed. Each is a real
control the design must address, not a disclaimer.

- **Heartbeats / timers.** A periodic "are you there?" turn that runs an LLM step on a schedule
  bills **every interval, forever, whether or not there's work.** A 5-minute heartbeat is
  **8,640 turns/month per agent** doing nothing. On the Opus reasoning profile above that's an
  idle floor of **~$1,160/mo per agent** — for zero delivered work. **Default heartbeats OFF; use
  event-driven wakes (cron/queue/Pub/Sub) instead.** If a heartbeat is unavoidable, put it on the
  cheapest model and the longest tolerable interval, and document the monthly token floor it creates.
- **Polling loops.** Any "check status every N seconds" loop that invokes the model is the same
  trap at higher frequency. Use push/event triggers; reserve polling for non-LLM health checks.
- **Idle reasoning / over-thinking.** High-reasoning/verbose modes multiply output tokens — and
  output is 5× input on most tiers. Match reasoning effort to task difficulty per agent role.
- **Context bloat.** Re-injecting large memory/transcript corpora every turn multiplies input
  tokens linearly with context size. Bound retrieval; summarize/compact long histories.
- **Retry storms.** A failing tool/model call retried in a tight loop bills each attempt. Cap
  retries; back off; alert.
- **Sub-agent fan-out.** One turn spawning many sub-agents multiplies spend per top-level action.
  Bound fan-out and make it deliberate.
- **Cloud-service egress on hot paths.** Frequent small reads from a metered object/secret store
  add up; cache where safe (and it's why ESO `refreshInterval` is hourly, not per-second).

**Guardrails this design wires in:**
- A per-agent **monthly spend cap / budget alert** at the billing layer (see [OPERATIONS](OPERATIONS.md#day-2--operate-run-it-like-it-matters)).
- Token/turn **observability** (log tokens-in/out per turn) so the bill is attributable per agent.
- A documented **token floor** for any always-on behavior (heartbeat/poll), reviewed before merge.

---

## 4. Total Cost of Ownership (rollup)

| Plane | Monthly est. | Driver | Lever |
|---|---|---|---|
| Infrastructure (hybrid) | **≈ $7–10** | electricity + a few near-free cloud services | profile choice (local vs managed) |
| Model / runtime | **≈ $14–160 / agent** | turn volume × tier | routing + reasoning effort + spend caps |
| **TCO (one small fleet)** | **runtime-dominated** | | the substrate is the rounding error |

*Break-even / ROI:* the design pays for itself the first time a node dies and the fleet keeps
running — a re-host that would be hours of manual recovery on the single-process baseline is a
non-event here (a new pod pulls its state and resumes). And because spend is instrumented per
agent, the more expensive plane — model inference — is the one we can actually see and control.
Tie the headline figure back to the README [Business Case](../README.md#business-case).
