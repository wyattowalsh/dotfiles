#!/usr/bin/env bash
set -euo pipefail

bash -n setup.sh bootstrap/macos.sh checks/ai-check.sh checks/ai-negative-check.sh checks/secrets-scan.sh checks/smoke.sh checks/validate-json.sh checks/zsh-inventory.sh

if [ "$(uname -s)" = "Darwin" ]; then
  ./bootstrap/macos.sh --dry-run >/dev/null
  set +e
  conflict_output="$(./bootstrap/macos.sh --dry-run --apply 2>&1 >/dev/null)"
  conflict_status=$?
  set -e

  if [ "$conflict_status" -ne 2 ]; then
    printf 'Expected conflicting bootstrap flags to exit 2, got %s\n' "$conflict_status" >&2
    exit 1
  fi

  if ! printf '%s\n' "$conflict_output" | rg -q -- '--dry-run and --apply cannot be used together'; then
    printf 'Expected conflicting bootstrap flags to print a clear error\n' >&2
    exit 1
  fi
else
  ./setup.sh --dry-run --verbose >/dev/null
fi

echo "Smoke checks completed."
