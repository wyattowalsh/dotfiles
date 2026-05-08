#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for JSON validation" >&2
  exit 1
fi

find . \
  -path './.git' -prune -o \
  -path './docs/node_modules' -prune -o \
  -path './docs/.next' -prune -o \
  -name '*.json' -print0 \
  | xargs -0 -r -n 1 jq empty

