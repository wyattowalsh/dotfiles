#!/usr/bin/env bash
# Fixture-TDD for zsh-structure.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STRUCT="$ROOT/checks/zsh-structure.sh"
FIX="$ROOT/checks/fixtures/zshrc"
fail=0

for b in "$FIX"/bad-*.zshrc; do
  if "$STRUCT" "$b" all >/dev/null 2>&1; then
    echo "FAIL: expected structure fail on $b" >&2
    fail=1
  else
    echo "OK fail: $(basename "$b")"
  fi
done

if ! "$STRUCT" "$FIX/good-minimal.zshrc" all; then
  echo "FAIL: expected structure pass on good-minimal.zshrc" >&2
  fail=1
fi

exit "$fail"
