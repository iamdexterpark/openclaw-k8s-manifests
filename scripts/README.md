# Scripts

Thin, sanitized helpers. They wrap the same commands the CI pipelines run, so you can
reproduce the gates locally before opening a PR. Placeholders (`example.internal`,
`REPLACE_*`) must be adapted to your environment.

| Script | Purpose | Used by |
|---|---|---|
| [`build_docs.py`](build_docs.py) | Inject `docs/diagrams/src/*.mermaid` into the `START/END_GENERATED` blocks across README + all `docs/*.md` (DRY). | docs build |
| [`validate.sh`](validate.sh) | Lint/build the deliverable, run the doc-sync check, scan tracked files for leaked secrets. | `validate` CI gate |

## Typical local loop

```bash
# after editing the deliverable or a doc
scripts/validate.sh                  # same gate CI runs
python3 scripts/build_docs.py        # if you touched a diagram source
```

## Notes

- `validate.sh` exits non-zero on any failure — wire it as a required status check.
- None of these apply anything to a live environment. Applying is the reconciler's job (or a
  deliberate, runbook-driven apply).
