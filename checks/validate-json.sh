#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for JSON validation" >&2
  exit 1
fi

while IFS= read -r -d '' json_file; do
  jq empty "$json_file"
done < <(
  find . \
    -path './.git' -prune -o \
    -path './docs/node_modules' -prune -o \
    -path './docs/.next' -prune -o \
    -name '*.json' -print0
)