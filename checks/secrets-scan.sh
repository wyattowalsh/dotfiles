#!/usr/bin/env bash
set -euo pipefail

if ! command -v rg >/dev/null 2>&1; then
  echo "ripgrep (rg) is required for secrets scanning" >&2
  exit 1
fi

patterns='(MCPHUB_BEARER_TOKEN": "[^$<]|api[_-]?key[[:space:]]*[:=][[:space:]]*["'\''][^$<]|token[[:space:]]*[:=][[:space:]]*["'\''][A-Za-z0-9_-]{20,}|secret[[:space:]]*[:=][[:space:]]*["'\''][^$<]|password[[:space:]]*[:=][[:space:]]*["'\''][^$<]|BEGIN (RSA|OPENSSH|EC|PRIVATE) KEY|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,})'

matches_file="$(mktemp)"

cleanup() {
  rm -f "$matches_file"
}
trap cleanup EXIT

while IFS= read -r -d '' tracked_file; do
  case "$tracked_file" in
    LICENSE|checks/secrets-scan.sh|checks/ai-check.sh|docs/node_modules/*|local/*|*.lock)
      continue
      ;;
  esac

  if rg -q -i "$patterns" -- "$tracked_file"; then
    printf '%s\n' "$tracked_file" >>"$matches_file"
  fi
done < <(git ls-files -z)

if [ -s "$matches_file" ]; then
  echo "Potential secret-shaped values found in tracked files:" >&2
  sort -u "$matches_file" >&2
  exit 1
fi
