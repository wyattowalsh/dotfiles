#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2317,SC2329 # Literal awk programs; cleanup is trap-invoked.
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

if ! "$STRUCT" "$ROOT/rig/dots/zshrc" L4; then
  echo "FAIL: canonical zsh contract failed" >&2
  fail=1
fi

CONTRACT_TMP="$(mktemp -d "${TMPDIR:-/tmp}/zsh-contract-test.XXXXXX")"
cleanup() {
  if [[ -n ${CONTRACT_TMP:-} && -d $CONTRACT_TMP && $CONTRACT_TMP == "${TMPDIR:-/tmp}"/zsh-contract-test.* ]]; then
    rm -rf -- "$CONTRACT_TMP"
  fi
}
trap cleanup EXIT

contract_fixture() {
  local name=$1
  local program=$2
  local fixture="$CONTRACT_TMP/$name.zshrc"
  awk "$program" "$ROOT/rig/dots/zshrc" >"$fixture"
  if "$STRUCT" "$fixture" L4 >/dev/null 2>&1; then
    echo "FAIL: expected L4 contract fail for $name" >&2
    fail=1
  else
    echo "OK contract fail: $name"
  fi
}

contract_fixture plugin-set '$0 == "  zsh-interactive-cd" { $0 = "  safe-paste" } { print }'
contract_fixture history-size '/^HISTSIZE=/ { $0 = "HISTSIZE=40000" } { print }'
contract_fixture managed-completion 'index($0, "$HOME/.zsh/completions(N)") { next } { print }'
contract_fixture custom-ysu '/unset _ysu _ysu_cand/ { print "  _ysu=${ZSH_CUSTOM}/plugins/you-should-use/you-should-use.plugin.zsh" } { print }'
contract_fixture highlighters '/^typeset -ga ZSH_HIGHLIGHT_HIGHLIGHTERS=/ { $0 = "typeset -ga ZSH_HIGHLIGHT_HIGHLIGHTERS=(main)" } { print }'

if ! "$ROOT/checks/zsh-home-behavior-test.sh"; then
  echo "FAIL: shell/home behavior checks failed" >&2
  fail=1
fi

exit "$fail"
