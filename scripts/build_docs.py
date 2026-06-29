#!/usr/bin/env python3
"""
build_docs.py — DRY Mermaid (and snippet) injector.

Single source of truth for every diagram/snippet is a file under docs/diagrams/src/
(or any path relative to the project root). Each target doc declares an injection
block:

    <!-- START_GENERATED:docs/diagrams/src/topology.mermaid -->
    ... (auto-filled; do not hand-edit) ...
    <!-- END_GENERATED:docs/diagrams/src/topology.mermaid -->

Run `python3 scripts/build_docs.py` after editing any source. Every copy across
README.md and everything under docs/ updates — no hand-syncing.

Improvements over the original hardcoded version:
  - Auto-discovers targets: README.md + all *.md under docs/ (recursively),
    so ADRs and runbooks that embed diagrams stay in sync too.
  - .mermaid sources are fenced as ```mermaid; any other extension is injected
    verbatim (use for shared text/code snippets).
  - Idempotent; exits non-zero on a missing source so CI catches drift.
"""
import os
import re
import sys
import glob

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)


def discover_targets():
    targets = []
    readme = os.path.join(PROJECT_ROOT, "README.md")
    if os.path.exists(readme):
        targets.append(readme)
    docs_dir = os.path.join(PROJECT_ROOT, "docs")
    if os.path.isdir(docs_dir):
        targets.extend(
            sorted(glob.glob(os.path.join(docs_dir, "**", "*.md"), recursive=True))
        )
    return targets


PATTERN = re.compile(
    r"(<!--\s*START_GENERATED:(?P<path>[a-zA-Z0-9_\-\./\+]+)\s*-->)"
    r"(.*?)"
    r"(<!--\s*END_GENERATED:(?P=path)\s*-->)",
    re.DOTALL | re.IGNORECASE,
)


def update_file(file_path):
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    matches = list(PATTERN.finditer(content))
    if not matches:
        return False

    new_content = content
    missing = []
    # reverse order keeps string indices valid as we splice
    for match in reversed(matches):
        start_tag, rel_path, end_tag = match.group(1), match.group("path"), match.group(4)
        src_path = os.path.join(PROJECT_ROOT, rel_path)
        if not os.path.exists(src_path):
            missing.append(rel_path)
            continue
        with open(src_path, "r", encoding="utf-8") as src_file:
            src_data = src_file.read().strip()
        if rel_path.endswith(".mermaid"):
            block = f"\n```mermaid\n{src_data}\n```\n"
        else:
            block = f"\n{src_data}\n"
        replacement = f"{start_tag}{block}{end_tag}"
        new_content = new_content[: match.start()] + replacement + new_content[match.end():]

    if missing:
        rel = os.path.relpath(file_path, PROJECT_ROOT)
        for m in missing:
            print(f"✗ Missing source: {m} (referenced in {rel})", file=sys.stderr)
        sys.exit(1)

    if new_content != content:
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(new_content)
        print(f"✓ Updated: {os.path.relpath(file_path, PROJECT_ROOT)}")
        return True
    print(f"– No changes: {os.path.relpath(file_path, PROJECT_ROOT)}")
    return False


def main():
    print("Building documentation diagrams...")
    targets = discover_targets()
    if not targets:
        print("No target docs found (expected README.md and/or docs/*.md).")
        return
    for target in targets:
        try:
            update_file(target)
        except SystemExit:
            raise
        except Exception as e:
            print(f"✗ Failed on {os.path.basename(target)}: {e}", file=sys.stderr)
            sys.exit(1)
    print("Documentation build completed.")


if __name__ == "__main__":
    main()
