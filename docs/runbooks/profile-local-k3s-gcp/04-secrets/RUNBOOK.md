# Runbook 04 — Secrets

> **Target Environment** (mandatory — a runbook that doesn't declare its env is a trap)
> | | |
> |---|---|
> | **Deployment profile** | `profile-local-k3s-gcp` (primary) |
> | **Substrate** | self-hosted K3s |
> | **Cloud services used** | Google Secret Manager (runtime source) |
> | **Identity model** | GCP Workload Identity (KSA ↔ GSA); sops/age seed for recovery |
> | **What changes under a different profile** | the `gcloud secrets` commands → that cloud's secret-manager CLI; the WI binding form |

**Goal:** get channel/model/auth secrets into the cluster the right way — resolved at runtime from
Secret Manager, never committed in plaintext, with a sops/age recovery seed in Git
([ADR-0002](../../adr/0002-secrets-external-operator-over-sealed-vault.md)).
**Time:** ~15 min · **Risk:** med · **Reversible:** yes (rotate)

## Model recap

```
sops/age sealed file (Git, recovery seed)  ──►  Google Secret Manager (runtime source)  ──ESO──►  K8s Secret  ──►  pod
```

See [HLD §7](../../HLD.md#7-controls-protocols--patterns) and [LLD §5](../../LLD.md#5-secrets--concrete-wiring).

## Steps

### 1. Generate the age key (one-time recovery seed)

```bash
age-keygen -o age-key.txt    # private key → recovery media, NEVER Git (it's in .gitignore)
```

Store the private key on **three independent recovery media** (e.g. a printed paper key in a safe, a
password-manager vault, and a hardware token). It is the break-glass path if Secret Manager contents
are ever lost.

### 2. Seal the seed into Git

```bash
sops --encrypt --age <recipient> secrets.plain.yaml > secrets.enc.yaml
git add secrets.enc.yaml .sops.yaml      # never secrets.plain.yaml (gitignored)
```

### 3. Load the live secrets into Secret Manager (per agent, least privilege)

```bash
gcloud secrets create agents/<id>/gateway-auth-password --replication-policy=automatic
printf '%s' "$VALUE" | gcloud secrets versions add agents/<id>/gateway-auth-password --data-file=-
# repeat for model-api-key and any bound channel tokens
```

### 4. Bind the agent's KSA to a least-privilege GSA (Workload Identity)

```bash
gcloud iam service-accounts add-iam-policy-binding \
  workload@REPLACE_PROJECT_ID.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:REPLACE_PROJECT_ID.svc.id.goog[<id>/<id>-workload]"
# grant that GSA read on only this agent's secret paths
```

## Verification

```bash
kubectl -n <id> get externalsecret agent-secrets -o wide          # STATUS: SecretSynced
kubectl -n <id> get secret <id>-agent-secrets -o jsonpath='{.data}' | jq 'keys'   # expected keys
git grep -nEi '(api[_-]?key|password|token).{0,3}[:=].{8,}' -- . ':!*.md'   # only sealed/placeholder
```

You should **never** see plaintext in Git or in a ConfigMap.

## Rollback / rotation

```bash
gcloud secrets versions add agents/<id>/model-api-key --data-file=-   # ESO picks it up within refreshInterval (1h)
# compromised age key → new key, re-seal all .enc.yaml, destroy the old key
```

## Notes / Gotchas

- ESO `refreshInterval` is 1h on purpose — a per-second refresh is a metered-op cost trap on the
  secret manager ([COST-MODEL §3](../../COST-MODEL.md#3-️-runtime-cost-traps-read-before-deploying)).
