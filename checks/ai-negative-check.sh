#!/usr/bin/env bash
set -euo pipefail

run_negative_case() {
  local name="$1"
  local mutation="$2"
  local tmpdir

  tmpdir="$(mktemp -d)"
  cp -R ai "$tmpdir/ai"

  case "$name" in
    missing-schema)
      rm "$tmpdir/ai/schemas/mcphub.schema.json"
      ;;
    *)
      jq "$mutation" "$tmpdir/ai/${name%%:*}" > "$tmpdir/ai/mutated.json"
      mv "$tmpdir/ai/mutated.json" "$tmpdir/ai/${name%%:*}"
      ;;
  esac

  if AI_DIR="$tmpdir/ai" ./checks/ai-check.sh >/dev/null 2>&1; then
    rm -rf "$tmpdir"
    printf 'Expected AI negative check to fail: %s\n' "$name" >&2
    exit 1
  fi

  rm -rf "$tmpdir"
}

run_negative_case "mcphub.manifest.json:unknown-root-key" '.unexpected = true'
run_negative_case "client-surfaces.json:unknown-client-key" '.clients[0].extra = "x"'
run_negative_case "client-surfaces.json:unknown-mcp-key" '.clients[0].mcp.extra = "x"'
run_negative_case "missing-schema" ''

echo "AI negative checks completed."
