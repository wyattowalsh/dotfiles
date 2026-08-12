#!/usr/bin/env bash
# Fail if rig/brew/exclude.txt tokens appear as brew/cask/tap entries in rig/brew/Brewfile.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BREWFILE="${1:-$REPO_DIR/rig/brew/Brewfile}"
EXCLUDE="${2:-$REPO_DIR/rig/brew/exclude.txt}"

if [[ ! -f "$BREWFILE" ]]; then
  printf 'Missing Brewfile: %s\n' "$BREWFILE" >&2
  exit 1
fi
if [[ ! -f "$EXCLUDE" ]]; then
  printf 'Missing exclude list: %s\n' "$EXCLUDE" >&2
  exit 1
fi

hits=0
while IFS= read -r line || [[ -n "$line" ]]; do
  # strip comments and whitespace
  token="${line%%#*}"
  token="$(printf '%s' "$token" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [[ -z "$token" ]] && continue

  if rg -q --fixed-strings "brew \"${token}\"" "$BREWFILE" \
    || rg -q --fixed-strings "cask \"${token}\"" "$BREWFILE" \
    || rg -q --fixed-strings "tap \"${token}\"" "$BREWFILE"; then
    printf 'exclude violation: %s still listed in %s\n' "$token" "$BREWFILE" >&2
    hits=$((hits + 1))
  fi
done <"$EXCLUDE"

if [[ "$hits" -gt 0 ]]; then
  printf 'brew-exclude-check: %s violation(s)\n' "$hits" >&2
  exit 1
fi

printf 'brew-exclude-check: ok\n'
