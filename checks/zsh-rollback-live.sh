#!/usr/bin/env bash
# Restore latest ~/.zshrc.bak.* (live cutover rollback).
set -euo pipefail

bak=""
while IFS= read -r -d '' candidate; do
  if [[ -z "$bak" || "$candidate" -nt "$bak" ]]; then
    bak=$candidate
  fi
done < <(find "$HOME" -maxdepth 1 -name '.zshrc.bak.*' -type f -print0 2>/dev/null)

if [[ -z ${bak:-} ]]; then
  echo "no ~/.zshrc.bak.* found" >&2
  exit 1
fi
cp -a "$bak" "$HOME/.zshrc"
echo "restored $bak -> ~/.zshrc"
