#!/usr/bin/env bash
# Structure gate for zshrc SSOT (CI-safe, file-only).
# Usage: ./checks/zsh-structure.sh [path] [L0|L1|L2|L3|all]
set -euo pipefail

f=${1:-rig/dots/zshrc}
lvl=${2:-all}

fail() {
  echo "FAIL(${lvl}): $*" >&2
  exit 1
}

[[ -f $f ]] || fail "missing $f"

if [[ $lvl == L0 || $lvl == all ]]; then
  if grep -Eiq 'amazon-q|Amazon Q|q init zsh' "$f"; then
    fail "Amazon Q present"
  fi
  if grep -Eq 'mise hook-env' "$f"; then
    fail "mise hook-env present"
  fi
  # gtimeout is Homebrew/coreutils; never alias timeout= on its own line
  if grep -Eq '^[[:space:]]*alias timeout=' "$f"; then
    fail "unguarded alias timeout= (guard with command -v gtimeout on the same line)"
  fi
  # secrets.env mode 600: BSD stat -f is not enough on Linux (need GNU stat -c)
  if grep -q 'secrets.env' "$f"; then
    if grep -Eq 'stat[[:space:]]+-f' "$f" && ! grep -Eq 'stat[[:space:]]+-c' "$f"; then
      fail "secrets.env gated only with BSD stat -f (need GNU stat -c too)"
    fi
  fi
fi

if [[ $lvl == L1 || $lvl == all ]]; then
  # Model A: no user-facing compinit in SSOT (OMZ runs one internally)
  if grep -Eiq '(^|[[:space:]])compinit([[:space:]]|$)' "$f"; then
    fail "user compinit present (Model A forbids SSOT compinit)"
  fi
  if ! grep -Eq 'zsh-completions' "$f"; then
    fail "zsh-completions not configured"
  fi
  # fpath block should appear before oh-my-zsh source
  fpath_line=$(grep -n 'fpath=(' "$f" | head -1 | cut -d: -f1 || true)
  omz_line=$(grep -n 'oh-my-zsh.sh' "$f" | head -1 | cut -d: -f1 || true)
  if [[ -n ${fpath_line:-} && -n ${omz_line:-} && $fpath_line -gt $omz_line ]]; then
    fail "fpath configured after oh-my-zsh.sh (must be before)"
  fi
fi

if [[ $lvl == L2 || $lvl == all ]]; then
  plugins_block=$(awk '/plugins=\(/,/^\)/' "$f" 2>/dev/null || true)
  if echo "$plugins_block" | grep -Eq '^[[:space:]]*pyenv[[:space:]]*$'; then
    fail "pyenv plugin present"
  fi
  if echo "$plugins_block" | grep -Eq '^[[:space:]]*poetry(-env)?[[:space:]]*$'; then
    fail "poetry plugin present"
  fi
  if ! grep -Eq 'PNPM_HOME' "$f"; then
    fail "missing PNPM_HOME"
  fi
  if ! grep -Eq 'PIPX_' "$f"; then
    fail "missing PIPX_ env"
  fi
  if ! grep -Eq 'mise activate' "$f"; then
    fail "missing mise activate"
  fi
fi

if [[ $lvl == L3 || $lvl == all ]]; then
  last=$(grep -E '^[[:space:]]*(source|builtin source|\.) ' "$f" | grep -v '^[[:space:]]*#' | tail -1 || true)
  if ! echo "$last" | grep -q 'syntax-highlighting'; then
    fail "highlight not last source: ${last:-<none>}"
  fi
fi

echo "OK $f $lvl"
