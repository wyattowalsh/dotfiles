#!/usr/bin/env bash
# Fail if the Fumadocs static export shipped uncompiled Tailwind CSS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CSS_DIR="$ROOT/docs/out/_next/static/chunks"

if [ ! -d "$CSS_DIR" ]; then
  printf 'docs-css-health: missing %s (run docs build first)\n' "$CSS_DIR" >&2
  exit 1
fi

# Collect CSS files (bash 3.2-safe; no mapfile).
css_files=()
while IFS= read -r -d '' f; do
  css_files+=("$f")
done < <(find "$CSS_DIR" -type f -name '*.css' -print0)

if [ "${#css_files[@]}" -eq 0 ]; then
  printf 'docs-css-health: no CSS chunks under %s\n' "$CSS_DIR" >&2
  exit 1
fi

# Positive: utilities compiled to real rules.
if ! rg -q -- '\.flex\{' "${css_files[@]}"; then
  printf 'docs-css-health: compiled .flex utility not found (Tailwind pipeline missing?)\n' >&2
  exit 1
fi

# Negative: unprocessed Tailwind v4 source markers left in the bundle.
if rg -q -- '@apply |@source inline' "${css_files[@]}"; then
  printf 'docs-css-health: unprocessed Tailwind directives remain in built CSS\n' >&2
  rg -n -- '@apply |@source inline' "${css_files[@]}" | head -20 >&2 || true
  exit 1
fi

printf 'docs-css-health: ok (%s css files)\n' "${#css_files[@]}"
