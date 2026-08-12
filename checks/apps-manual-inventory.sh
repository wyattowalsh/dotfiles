#!/usr/bin/env bash
# Write basenames of apps under /Applications and ~/Applications.
# Paths are never written — basenames only (privacy-safe inventory evidence).
set -euo pipefail

output="${1:-local/apps-all.txt}"
mkdir -p "$(dirname "$output")"

{
  if [[ -d /Applications ]]; then
    # shellcheck disable=SC2012
    ls /Applications 2>/dev/null | sed 's/\.app$//'
  fi
  if [[ -d "${HOME}/Applications" ]]; then
    # shellcheck disable=SC2012
    ls "${HOME}/Applications" 2>/dev/null | sed 's/\.app$//'
  fi
} | sort -u >"${output}"

if grep -q '/Users/' "${output}" 2>/dev/null; then
  printf 'Privacy error: absolute user paths found in %s\n' "${output}" >&2
  exit 1
fi

printf 'Wrote app basenames to %s (%s entries)\n' "${output}" "$(wc -l <"${output}" | tr -d ' ')"
