#!/usr/bin/env bash
# Ensure docs hub-manifest slugs match sidebar meta.json content pages.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
META="$ROOT/docs/content/docs/meta.json"
MANIFEST="$ROOT/docs/lib/hub-manifest.json"

if [[ ! -f "$META" || ! -f "$MANIFEST" ]]; then
  echo "docs-hub-parity: missing meta or hub-manifest" >&2
  exit 1
fi

python3 - "$META" "$MANIFEST" <<'PY'
import json
import sys
from pathlib import Path

meta_path = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])

meta = json.loads(meta_path.read_text())
manifest = json.loads(manifest_path.read_text())

meta_pages = {
    page
    for page in meta.get("pages", [])
    if isinstance(page, str) and not page.startswith("---") and page != "index"
}

sections = manifest.get("sections", [])
if not isinstance(sections, list) or not sections:
    print("docs-hub-parity: hub-manifest.sections must be a non-empty list", file=sys.stderr)
    sys.exit(1)

required = {"slug", "title", "description", "group"}
allowed_groups = {"start", "operate", "reference"}
manifest_slugs: set[str] = set()
errors: list[str] = []

for i, section in enumerate(sections):
    if not isinstance(section, dict):
        errors.append(f"section[{i}] is not an object")
        continue
    missing = required - set(section)
    if missing:
        errors.append(f"section[{i}] missing fields: {sorted(missing)}")
        continue
    slug = section["slug"]
    group = section["group"]
    if not isinstance(slug, str) or not slug:
        errors.append(f"section[{i}] has invalid slug")
        continue
    if group not in allowed_groups:
        errors.append(f"section[{i}] ({slug}) has invalid group: {group}")
    if slug in manifest_slugs:
        errors.append(f"duplicate slug: {slug}")
    manifest_slugs.add(slug)
    for field in ("title", "description"):
        if not isinstance(section[field], str) or not section[field].strip():
            errors.append(f"section[{i}] ({slug}) empty {field}")

only_meta = sorted(meta_pages - manifest_slugs)
only_manifest = sorted(manifest_slugs - meta_pages)
if only_meta:
    errors.append(f"in meta.json but missing from hub-manifest: {only_meta}")
if only_manifest:
    errors.append(f"in hub-manifest but missing from meta.json: {only_manifest}")

if errors:
    print("docs-hub-parity: FAIL", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    sys.exit(1)

print(f"docs-hub-parity: ok ({len(manifest_slugs)} slugs)")
PY
