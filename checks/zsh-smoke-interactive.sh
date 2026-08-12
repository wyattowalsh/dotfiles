#!/usr/bin/env bash
# Local-only interactive smoke (not for bare Ubuntu CI).
set -euo pipefail

if ! command -v zsh >/dev/null 2>&1; then
  echo "zsh missing; skip"
  exit 0
fi

zsh -i -c '
  set -e
  command -v uv >/dev/null
  command -v uvx >/dev/null
  command -v pnpm >/dev/null
  command -v pipx >/dev/null
  command -v mise >/dev/null
  command -v zoxide >/dev/null
  [[ -n ${PNPM_HOME:-} ]]
  [[ -n ${PIPX_BIN_DIR:-} ]]
  # zoxide init should define z or __zoxide_z
  (( $+functions[__zoxide_z] || $+aliases[z] || $+functions[z] ))
  # syntax highlighting loaded
  typeset -f _zsh_highlight >/dev/null || typeset -f _zsh_highlight_call_widget >/dev/null
  print OK smoke
'
