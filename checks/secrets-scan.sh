#!/usr/bin/env bash
set -euo pipefail

patterns='(MCPHUB_BEARER_TOKEN": "[^$<]|api[_-]?key[[:space:]]*[:=][[:space:]]*["'\''][^$<]|token[[:space:]]*[:=][[:space:]]*["'\''][A-Za-z0-9_-]{20,}|secret[[:space:]]*[:=][[:space:]]*["'\''][^$<]|password[[:space:]]*[:=][[:space:]]*["'\''][^$<]|BEGIN (RSA|OPENSSH|EC|PRIVATE) KEY|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,})'

if rg -n -i "$patterns" \
  -g '!LICENSE' \
  -g '!checks/secrets-scan.sh' \
  -g '!checks/ai-check.sh' \
  -g '!docs/node_modules/**' \
  -g '!local/**' \
  -g '!*.lock' \
  .; then
  echo "Potential secret-shaped values found." >&2
  exit 1
fi
