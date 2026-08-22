#!/usr/bin/env bash
# Apple Text Replacement + Shortcuts registry CLI. Default is dry-run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/checks/apple_text_cli.py"

if ! command -v python3 >/dev/null 2>&1; then
  printf 'apple-text: python3 is required\n' >&2
  exit 1
fi

if command -v uv >/dev/null 2>&1; then
  exec uv run python "$CLI" "$@"
fi
exec python3 "$CLI" "$@"
