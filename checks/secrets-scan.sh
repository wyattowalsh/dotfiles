#!/usr/bin/env bash
# Scan tracked files for secret-shaped values. Report filenames only.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v rg >/dev/null 2>&1; then
  echo "ripgrep (rg) is required for secrets scanning" >&2
  exit 1
fi

# Quoted KEY=value (skip $ / < placeholders). Unquoted assignments require 20+ char
# values so synthetic fixtures like api_key=secret-value do not fail CI.
# PEM: BEGIN [RSA|OPENSSH|EC|DSA|ENCRYPTED] PRIVATE KEY (not BEGIN RSA KEY).
rg_opts=(
  -q
  -i
  -e 'MCPHUB_BEARER_TOKEN": "[^$<]'
  -e '(password|secret|token|api[_-]?key)[[:space:]]*[:=][[:space:]]*["'\''][^$<"'\''[:space:]]'
  -e '(password|secret|token|api[_-]?key)[[:space:]]*[:=][[:space:]]*[^$<"'\''[:space:]][^[:space:]]{19,}'
  -e 'ghp_[A-Za-z0-9]{20,}'
  -e 'github_pat_[A-Za-z0-9_]{20,}'
  -e 'gho_[A-Za-z0-9]{20,}'
  -e 'xox[baprs]-[A-Za-z0-9-]+'
  -e 'BEGIN ((RSA|OPENSSH|EC|DSA|ENCRYPTED) )?PRIVATE KEY'
  -e 'AKIA[0-9A-Z]{16}'
  -e 'sk-[A-Za-z0-9]{20,}'
)

skip_file() {
  case "$1" in
    LICENSE|checks/secrets-scan.sh|checks/docs-sensitive.sh) return 0 ;;
    docs/node_modules/*|local/*|*.lock|.env.example) return 0 ;;
    */tests/fixtures/*) return 0 ;;
  esac
  return 1
}

matches_file="$(mktemp)"

cleanup() {
  rm -f "$matches_file"
}
trap cleanup EXIT

while IFS= read -r -d '' tracked_file; do
  if skip_file "$tracked_file"; then
    continue
  fi

  if [ ! -f "$tracked_file" ]; then
    continue
  fi

  if rg "${rg_opts[@]}" -- "$tracked_file"; then
    printf '%s\n' "$tracked_file" >>"$matches_file"
  fi
done < <(git ls-files -z)

if [ -s "$matches_file" ]; then
  echo "Potential secret-shaped values found in tracked files:" >&2
  sort -u "$matches_file" >&2
  exit 1
fi
