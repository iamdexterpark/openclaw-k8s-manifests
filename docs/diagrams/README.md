# Diagrams

Mermaid sources for the design docs. The files under [`src/`](src/) are the **single source
of truth** for every diagram in this repo. The build tool
([`../../scripts/build_docs.py`](../../scripts/build_docs.py)) injects each
`src/*.mermaid` file into the matching

```
<!-- START_GENERATED:docs/diagrams/src/<name>.mermaid -->
... (auto-filled) ...
<!-- END_GENERATED:docs/diagrams/src/<name>.mermaid -->
```

block across `README.md` and every `*.md` under `docs/` (README, HLD, LLD, ADRs, runbooks).
Edit the `.mermaid` file, run the build, and every copy updates — no hand-syncing.

| Source | What it shows | Leads |
|---|---|---|
| `hero.mermaid` | The whole story in one picture: single process → stateless fleet, with config/secrets/state externalized (agnostic-ish, role-generic). | README |
| `hld_overview.mermaid` | The keystone primitives and their relationships, role-generic — NO products. | HLD |
| `lld_topology.mermaid` | The same shape made concrete for the primary profile: K3s, GCS, GSM, ESO, Pub/Sub. | LLD |
| `architecture_at_a_glance.mermaid` | The transformation (one process → fleet), vendor-agnostic. | README §Architecture, HLD §Architecture |
| `lifecycle.mermaid` | The lifecycle state machine: provision → deploy → operate → recover → decommission, mapped to runbooks. | README, HLD, OPERATIONS |

## Conventions

- One concept per diagram. If it needs a legend, it's two diagrams.
- Color load-bearing nodes consistently (e.g. red = the problem/constraint, green = the
  desired end state). Keep a stable palette across diagrams in the repo.
- Mermaid over ASCII art, always.

## Rendering

GitHub renders Mermaid in fenced ```` ```mermaid ```` blocks natively, so injected copies
display inline. Regenerate after editing a source:

```bash
python3 scripts/build_docs.py
```
