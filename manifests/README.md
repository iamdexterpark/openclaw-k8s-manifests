# Manifests

The deliverable: Kustomize-structured, declarative manifests that turn a single-process runtime into
a **pod-per-agent fleet**. Everything here is generic and sanitized — placeholder registries, example
hostnames, no real tokens. A reference implementation, not a drop-in production deploy.

```
manifests/
├── base/                      # one reusable agent primitive (the unit of the fleet)
│   ├── kustomization.yaml     # bare image NAME only; overlay owns newName + @sha256
│   ├── serviceaccount.yaml    # KSA; Workload Identity annotation added per overlay
│   ├── deployment.yaml        # replicas:1 + Recreate; RO config; emptyDir scratch
│   ├── service.yaml           # ClusterIP 80 → 18789, fronted by mesh
│   ├── configmap.yaml         # persona + agent config (mounted read-only)
│   ├── externalsecret.yaml    # secret-manager key REFERENCES (no values)
│   ├── networkpolicy.yaml     # default-deny ingress + egress
│   └── pdb.yaml               # guard the single writer
│
├── overlays/
│   └── example/               # onboarding one agent = one overlay
│       ├── kustomization.yaml # namespace + namePrefix + newName + @sha256 digest pin
│       ├── namespace.yaml
│       ├── patch-serviceaccount.yaml  # bind KSA → GSA (Workload Identity)
│       ├── patch-config.yaml          # agent id / model / channel binding
│       └── patch-externalsecret.yaml  # this agent's secret paths (least privilege)
│
└── platform/                  # cluster-scoped shared primitives
    ├── kustomization.yaml
    ├── namespace.yaml
    ├── external-secrets/clustersecretstore.yaml   # ESO → secret manager via Workload Identity
    └── backup/cronjob-restic.yaml                 # hourly backup + weekly restore-drill
```

The decisions encoded here are argued in the [ADRs](../docs/adr/README.md) and the
[LLD](../docs/LLD.md). The image pin lives in the **overlay**, not the base — a base rename can
silently drop an overlay's digest, so `scripts/validate.sh` asserts every overlay renders an
`@sha256` pin.

## Render & apply

```bash
kustomize build manifests/platform        | kubectl apply -f -
kustomize build manifests/overlays/example | kubectl apply -f -
```
