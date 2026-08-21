#!/usr/bin/env bash
# Fail if mise is used as a second task runner in this repo.
# just owns recipes; mise owns toolchain versions only.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail() {
  printf 'mise-boundary: %s\n' "$*" >&2
  exit 1
}

if [ -f mise.toml ] || [ -f .mise.toml ]; then
  fail "repo-root mise.toml is forbidden; just owns workflows"
fi

while IFS= read -r -d '' f; do
  if rg -q '^\[tasks\]' "$f"; then
    fail "mise [tasks] in $f would rival just; remove it"
  fi
done < <(find . \
  \( -name .git -o -name local -o -name node_modules -o -name .next \) -prune \
  -o \( -name 'mise.toml' -o -name '.mise.toml' \) -print0 2>/dev/null)

printf 'mise-boundary: ok\n'
