#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for AI config validation" >&2
  exit 1
fi

AI_DIR="${AI_DIR:-ai}"
MCPHUB_MANIFEST="${AI_DIR}/mcphub.manifest.json"
CLIENT_SURFACES="${AI_DIR}/client-surfaces.json"

validate_json() {
  local path="$1"

  jq empty "$path"
}

validate_schema_reference() {
  local manifest="$1"
  local schema_ref schema_path

  schema_ref="$(jq -r '."$schema" // empty' "$manifest")"
  if [ -z "$schema_ref" ]; then
    echo "${manifest} is missing a \$schema reference" >&2
    exit 1
  fi

  schema_path="${AI_DIR}/${schema_ref#./}"
  if [ ! -f "$schema_path" ]; then
    echo "${manifest} references missing schema: ${schema_path}" >&2
    exit 1
  fi

  validate_json "$schema_path"
}

validate_json "$MCPHUB_MANIFEST"
validate_json "$CLIENT_SURFACES"
validate_schema_reference "$MCPHUB_MANIFEST"
validate_schema_reference "$CLIENT_SURFACES"

jq -e '
  def exact($allowed): (keys | sort) == ($allowed | sort);

  exact(["$schema", "version", "transport", "endpoints", "fallbackServers"]) and
  ."$schema" == "./schemas/mcphub.schema.json" and
  (.version | type == "number" and . >= 1 and . == floor) and
  (.transport | type == "object") and
  (.transport | exact(["type", "command", "bearerTokenEnv"])) and
  (.transport.type == "stdio") and
  (.transport.command | type == "string" and length > 0) and
  (.transport.bearerTokenEnv == "MCPHUB_BEARER_TOKEN") and
  (.endpoints | type == "object") and
  (.endpoints | exact(["all", "groups"])) and
  (.endpoints.all | type == "string" and test("^https?://")) and
  (.endpoints.groups | type == "object" and length > 0) and
  all(.endpoints.groups[]; type == "string" and test("^https?://")) and
  (.fallbackServers | type == "array" and length > 0 and length == (unique | length)) and
  all(.fallbackServers[]; type == "string" and length > 0)
' "$MCPHUB_MANIFEST" >/dev/null || {
  echo "${MCPHUB_MANIFEST} does not match the tracked MCPHub manifest contract" >&2
  exit 1
}

jq -e '
  def exact($allowed): (keys | sort) == ($allowed | sort);

  exact(["$schema", "clients"]) and
  ."$schema" == "./schemas/client-surfaces.schema.json" and
  (.clients | type == "array" and length > 0) and
  all(.clients[];
    (type == "object") and
    exact(["id", "surface", "format", "mcp"] + (if has("notes") then ["notes"] else [] end)) and
    (.id | type == "string" and length > 0) and
    (.surface | type == "string" and length > 0) and
    (.format == "json" or .format == "toml") and
    (.mcp | type == "object") and
    (.mcp | exact(["default", "fallback"])) and
    (.mcp.default == "mcphub" or .mcp.default == "direct") and
    (.mcp.fallback == "direct" or .mcp.fallback == "none") and
    ((has("notes") | not) or (.notes | type == "string" and length > 0))
  ) and
  ([.clients[].id] | length == (unique | length))
' "$CLIENT_SURFACES" >/dev/null || {
  echo "${CLIENT_SURFACES} does not match the tracked client surface contract" >&2
  exit 1
}

if ! command -v rg >/dev/null 2>&1; then
  echo "ripgrep (rg) is required for AI manifest secret scanning" >&2
  exit 1
fi

if rg -n 'MCPHUB_BEARER_TOKEN": "[^$<]' "$AI_DIR" .copilot .config/claude 2>/dev/null; then
  echo "Literal MCPHub bearer token detected; use \${MCPHUB_BEARER_TOKEN}." >&2
  exit 1
fi

if ! jq -e '.clients[] | select(.mcp.default == "mcphub")' "$CLIENT_SURFACES" >/dev/null; then
  echo "At least one AI client must default to MCPHub." >&2
  exit 1
fi
