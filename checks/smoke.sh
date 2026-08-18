#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" = "Darwin" ]; then
  # Dry-run may exit 1 when read-only probes fail (e.g. brew bundle check)
  # after printing a full plan. Accept 0 or 1 if the preview completed.
  set +e
  dry_output="$(./rig/bootstrap/macos.sh --dry-run 2>&1)"
  dry_status=$?
  set -e
  if [ "$dry_status" -ne 0 ] && [ "$dry_status" -ne 1 ]; then
    printf 'Expected bootstrap --dry-run to exit 0 or 1, got %s\n' "$dry_status" >&2
    printf '%s\n' "$dry_output" >&2
    exit 1
  fi
  if ! printf '%s\n' "$dry_output" | rg -q 'Bootstrap preview complete'; then
    printf 'Expected bootstrap --dry-run to finish the full preview plan\n' >&2
    printf '%s\n' "$dry_output" >&2
    exit 1
  fi

  set +e
  conflict_output="$(./rig/bootstrap/macos.sh --dry-run --apply 2>&1 >/dev/null)"
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
  set +e
  dry_output="$(./setup.sh --dry-run --verbose 2>&1)"
  dry_status=$?
  set -e
  if [ "$dry_status" -ne 0 ]; then
    printf 'Expected setup.sh --dry-run to exit 0, got %s\n' "$dry_status" >&2
    printf '%s\n' "$dry_output" >&2
    exit 1
  fi
  if ! printf '%s\n' "$dry_output" | rg -q 'setup.sh finished'; then
    printf 'Expected setup.sh --dry-run to print a finished summary\n' >&2
    printf '%s\n' "$dry_output" >&2
    exit 1
  fi
fi

echo "Smoke checks completed."
