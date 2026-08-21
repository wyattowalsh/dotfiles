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
  # tracked aliases file sourced
  (( $+aliases[c] && $+aliases[zshreload] && $+aliases[zshaliases] ))
  (( $+aliases[opc] && $+aliases[opa] && $+aliases[cdx] && $+aliases[cda] && $+aliases[grk] && $+aliases[cur] && $+aliases[agt] && $+aliases[frn] && $+aliases[bi] && $+aliases[als] && $+functions[alias-help] ))
  (( ! $+aliases[gm] && ! $+aliases[gm3] && ! $+aliases[gmy] ))
  # syntax highlighting loaded
  typeset -f _zsh_highlight >/dev/null || typeset -f _zsh_highlight_call_widget >/dev/null
  if (( $+commands[atuin] )); then
    (( $+widgets[atuin-search] || $+widgets[_atuin_search_widget] || $+functions[_atuin_search] ))
  fi
  if (( $+commands[dust] )); then
    [[ ${aliases[du]} == dust ]]
  fi
  if (( $+commands[duf] )); then
    [[ ${aliases[df]} == duf ]]
  fi
  (( $+aliases[atuin-agents] ))
  print OK smoke
'
