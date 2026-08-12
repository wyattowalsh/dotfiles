#!/usr/bin/env bash
# Fail if docs content contains common sensitive/PII patterns.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v rg >/dev/null 2>&1; then
  echo "ripgrep (rg) is required" >&2
  exit 1
fi

fail=0

scan() {
  local label="$1"
  local pattern="$2"
  local paths=("${@:3}")
  local hits
  hits="$(rg -n -e "$pattern" "${paths[@]}" 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    echo "FAIL [$label]:"
    echo "$hits"
    fail=1
  fi
}

scan "absolute-home-path" '/Users/[A-Za-z0-9._-]+/' docs/content docs/app README.md
scan "private-key-block" 'BEGIN (RSA|OPENSSH|EC|PRIVATE) KEY' docs/content docs/app
scan "aws-access-key" 'AKIA[0-9A-Z]{16}' docs/content docs/app
scan "openai-sk" 'sk-[A-Za-z0-9]{20,}' docs/content docs/app
# Non-empty env-style secret assignment in docs (names alone OK)
scan "token-literal-assign" '(MCPHUB_BEARER_TOKEN|BRAVE_API_KEY|API_KEY|TOKEN)\s*=\s*["'\''][^$<"'\''\s]' docs/content docs/app

if [[ "$fail" -ne 0 ]]; then
  echo "docs-sensitive: found sensitive patterns" >&2
  exit 1
fi

echo "docs-sensitive: ok"
