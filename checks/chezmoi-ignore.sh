#!/usr/bin/env bash
# just check-chezmoi-ignore
# Chezmoi .chezmoiignore matches destination/target paths, not source names.
# Fail if source-style names are used, or required target ignores are missing.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IGNORE="${1:-$REPO_DIR/rig/home/.chezmoiignore}"

if [[ ! -f "$IGNORE" ]]; then
  printf 'Missing chezmoi ignore file: %s\n' "$IGNORE" >&2
  exit 1
fi

fail=0

if rg -q -- '^[[:space:]]*dot_zshrc(\.tmpl)?[[:space:]]*$' "$IGNORE" \
  || rg -q -- '^[[:space:]]*dot_p10k\.zsh[[:space:]]*$' "$IGNORE"; then
  printf 'chezmoi-ignore: source-style names (dot_zshrc / dot_p10k.zsh) match nothing; use target paths\n' >&2
  fail=1
fi

for target in '.zshrc' '.p10k.zsh' 'AGENTS.md'; do
  if ! rg -qxF -- "$target" "$IGNORE"; then
    printf 'chezmoi-ignore: missing required target ignore: %s\n' "$target" >&2
    fail=1
  fi
done

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

printf 'chezmoi-ignore: ok\n'
