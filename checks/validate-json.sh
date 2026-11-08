#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for JSON validation" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

while IFS= read -r -d '' json_file; do
  [[ -f "$json_file" ]] || continue # Git tracks approved removals until the next commit.
  jq empty "$json_file"
done < <(git ls-files -z -- '*.json')
