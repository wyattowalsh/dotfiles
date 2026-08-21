#!/usr/bin/env bash
# just check-darwin-lock
# Static contract for the nix-darwin flake pin (no nix required).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$ROOT/rig/darwin/flake.lock"
FLAKE="$ROOT/rig/darwin/flake.nix"

fail=0
pin=""

fail_msg() {
  printf 'darwin-lock: %s\n' "$*" >&2
  fail=1
}

if ! command -v jq >/dev/null 2>&1; then
  printf 'darwin-lock: jq is required\n' >&2
  exit 1
fi

if [[ ! -f "$LOCK" ]]; then
  fail_msg "missing $LOCK"
elif ! jq empty "$LOCK" >/dev/null 2>&1; then
  fail_msg "flake.lock is not valid JSON"
else
  pin="$(jq -r '
    .nodes["nix-darwin"] as $n |
    if ($n | type) != "object" then
      empty
    elif ($n.locked.owner // "") != "" and ($n.locked.repo // "") != "" and ($n.locked.rev // "") != "" then
      "\($n.locked.owner)/\($n.locked.repo)/\($n.locked.rev)"
    elif ($n.original.owner // "") != "" and ($n.original.repo // "") != "" and (($n.locked.url // "") | test("/archive/[^/]+\\.tar\\.gz$")) then
      ($n.locked.url | capture(".*/archive/(?<rev>[^/]+)\\.tar\\.gz") | .rev) as $rev |
      "\($n.original.owner)/\($n.original.repo)/\($rev)"
    else
      empty
    end
  ' "$LOCK")"
  if [[ -z "$pin" ]]; then
    fail_msg "nix-darwin pin not recoverable (need locked.owner/repo/rev or original.owner/repo plus locked.url archive SHA)"
  fi
fi

if [[ ! -f "$FLAKE" ]]; then
  fail_msg "missing $FLAKE"
elif ! grep -Fq 'darwinConfigurations."w4w-mbp"' "$FLAKE"; then
  fail_msg 'flake.nix must contain darwinConfigurations."w4w-mbp"'
fi

if [[ "$fail" -ne 0 ]]; then
  printf 'darwin-lock: FAIL\n' >&2
  exit 1
fi

printf 'darwin-lock: ok (nix-darwin %s)\n' "$pin"
