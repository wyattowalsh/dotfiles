#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for AI config validation" >&2
  exit 1
fi

jq empty ai/mcphub.manifest.json
jq empty ai/client-surfaces.json

if rg -n 'MCPHUB_BEARER_TOKEN": "[^$<]' ai .copilot .config/claude 2>/dev/null; then
  echo "Literal MCPHub bearer token detected; use \${MCPHUB_BEARER_TOKEN}." >&2
  exit 1
fi

if ! jq -e '.clients[] | select(.mcp.default == "mcphub")' ai/client-surfaces.json >/dev/null; then
  echo "At least one AI client must default to MCPHub." >&2
  exit 1
fi

