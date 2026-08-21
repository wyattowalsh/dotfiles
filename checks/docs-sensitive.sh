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

# Policy prose that names /Users/ only to forbid it (placeholders, not a live path).
is_users_policy_prose() {
  local line="$1"
  [[ "$line" == *'/Users/<'* ]] && return 0
  [[ "$line" == *'/Users/…'* ]] && return 0
  [[ "$line" == *'/Users/...'* ]] && return 0
  return 1
}

report_hits() {
  local label="$1"
  local hits="$2"
  echo "FAIL [$label]:"
  if [[ "$label" == "absolute-home-path" ]]; then
    printf '%s\n' "$hits"
  else
    # file:line only — never echo matched secret-shaped text
    printf '%s\n' "$hits" | awk -F: '{print $1":"$2}'
  fi
}

scan() {
  local label="$1"
  local pattern="$2"
  local paths=("${@:3}")
  local hits filtered hit
  hits="$(rg -n -e "$pattern" "${paths[@]}" 2>/dev/null || true)"
  if [[ -z "$hits" ]]; then
    return 0
  fi

  if [[ "$label" == "absolute-home-path" ]]; then
    filtered=""
    while IFS= read -r hit; do
      [[ -z "$hit" ]] && continue
      if is_users_policy_prose "$hit"; then
        continue
      fi
      if [[ -n "$filtered" ]]; then
        filtered+=$'\n'
      fi
      filtered+="$hit"
    done <<<"$hits"
    hits="$filtered"
  fi

  if [[ -n "$hits" ]]; then
    report_hits "$label" "$hits"
    fail=1
  fi
}

# Username after /Users/ — trailing slash not required. Policy placeholders are allowlisted.
scan "absolute-home-path" '/Users/[^\s/]+' docs/content docs/app README.md
scan "private-key-block" 'BEGIN ((RSA|OPENSSH|EC|DSA|ENCRYPTED) )?PRIVATE KEY' docs/content docs/app
scan "aws-access-key" 'AKIA[0-9A-Z]{16}' docs/content docs/app
scan "openai-sk" 'sk-[A-Za-z0-9]{20,}' docs/content docs/app
# Non-empty env-style secret assignment in docs (names alone OK)
scan "token-literal-assign" '(MCPHUB_BEARER_TOKEN|BRAVE_API_KEY|API_KEY|TOKEN)\s*=\s*["'\''][^$<"'\''\s]' docs/content docs/app

if [[ "$fail" -ne 0 ]]; then
  echo "docs-sensitive: found sensitive patterns" >&2
  exit 1
fi

echo "docs-sensitive: ok"
