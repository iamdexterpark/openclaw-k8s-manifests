# Runbook 01 — Build the Image

> **Target Environment** (mandatory — a runbook that doesn't declare its env is a trap)
> | | |
> |---|---|
> | **Deployment profile** | `_common` — profile-independent (same on local K3s or any managed K8s) |
> | **Substrate** | any OCI builder; no cluster required |
> | **Cloud services used** | image registry only |
> | **Identity model** | registry push credential |
> | **What changes under a different profile** | nothing — the image is portable; only *where it's pushed* may differ |

**Goal:** turn the single-process runtime CLI into a non-root, digest-pinned OCI image the fleet can
run identically for every agent.
**Time:** ~10 min · **Risk:** low · **Reversible:** yes (overlays keep the prior digest in Git)

## Prerequisites

- A container build tool (`docker buildx` / `podman` / `kaniko` in CI).
- A registry you control (placeholder: `registry.example.internal`).
- A vulnerability scanner (`trivy`/`grype`) and a signer (`cosign`).

## Steps

### 1. Pin the runtime version

```bash
RUNTIME_VERSION="REPLACE_VERSION"   # pin; never 'latest'
```

### 2. Build (non-root, immutable-config mode baked in)

```dockerfile
FROM node:22-bookworm-slim
RUN useradd -u 10001 -m app
ARG RUNTIME_VERSION
RUN npm install -g "openclaw-cli@${RUNTIME_VERSION}"
ENV OPENCLAW_NIX_MODE=1            # config immutability (ADR-0006)
USER 10001
WORKDIR /work
ENTRYPOINT ["openclaw"]
CMD ["gateway", "start", "--config", "/config/openclaw.json"]
```

```bash
docker buildx build \
  --build-arg RUNTIME_VERSION="${RUNTIME_VERSION}" \
  -t registry.example.internal/openclaw-runtime:"${RUNTIME_VERSION}" \
  --provenance=true --sbom=true \
  --push .
```

### 3. Scan

```bash
trivy image --exit-code 1 --severity HIGH,CRITICAL \
  registry.example.internal/openclaw-runtime:"${RUNTIME_VERSION}"
```

A HIGH/CRITICAL finding fails the build. Fix or accept-with-justification before proceeding.

### 4. Sign

```bash
cosign sign --yes registry.example.internal/openclaw-runtime:"${RUNTIME_VERSION}"
```

### 5. Capture the digest

```bash
DIGEST=$(docker buildx imagetools inspect \
  registry.example.internal/openclaw-runtime:"${RUNTIME_VERSION}" \
  --format '{{.Manifest.Digest}}')
echo "Pin overlays to: registry.example.internal/openclaw-runtime@${DIGEST}"
```

## Verification

```bash
cosign verify registry.example.internal/openclaw-runtime@${DIGEST}   # valid signature
```

- The **digest** — not the tag — is what overlays reference. Tags move; digests don't.

## Rollback

Overlays keep the prior digest in Git history. Rollback = revert the digest-bump PR.

## Notes / Gotchas

- The image is identical for every agent; identity/config arrives at runtime via the mounted
  ConfigMap + ExternalSecret. Never bake an agent's identity into the image.
