#!/usr/bin/env bash
# Focused contract for curated ecosystem refresh findings.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BREWFILE="$ROOT/rig/brew/Brewfile"
EXCLUDES="$ROOT/rig/brew/exclude.txt"
GITCONFIG="$ROOT/rig/dots/gitconfig"
ATTRIBUTES="$ROOT/rig/home/private_dot_config/git/attributes"
MACOS_DEFAULTS="$ROOT/rig/darwin/modules/macos-defaults.nix"

fail() {
  printf 'rig-ecosystem-assurance: %s\n' "$*" >&2
  exit 1
}

if rg -q '^brew "tmux"$' "$BREWFILE"; then
  rg -q '^brew "asheshgoplani/tap/agent-deck"$' "$BREWFILE" || fail "tmux is allowed only as the declared Agent Deck backend"
  ! rg -q '^tmux$' "$EXCLUDES" || fail "managed Agent Deck tmux must not also be excluded"
else
  [[ "$(rg -c '^tmux$' "$EXCLUDES")" -eq 1 ]] || fail "unmanaged tmux must appear exactly once in brew/exclude.txt"
fi
[[ "$(rg -c '^uv "nbdime"$' "$BREWFILE")" -eq 1 ]] || fail 'Brewfile must provide exactly one uv "nbdime" entry'

rg -q '^\*\.ipynb[[:space:]]+diff=jupyternotebook$' "$ATTRIBUTES" || fail "notebook diff attribute is missing"
rg -q '^\*\.ipynb[[:space:]]+merge=jupyternotebook$' "$ATTRIBUTES" || fail "notebook merge attribute is missing"
[[ "$(git config --file "$GITCONFIG" --get diff.jupyternotebook.command)" == "git-nbdiffdriver diff" ]] \
  || fail "nbdime diff driver must use the exact git-nbdiffdriver command"
[[ "$(git config --file "$GITCONFIG" --get merge.jupyternotebook.driver)" == 'git-nbmergedriver merge %O %A %B %L %P' ]] \
  || fail "nbdime merge driver must use the exact git-nbmergedriver command"
if git config --file "$GITCONFIG" --get alias.dft >/dev/null 2>&1; then
  fail "unapproved dft alias is present"
fi
if git config --file "$GITCONFIG" --get difftool.difftastic.cmd >/dev/null 2>&1; then
  fail "unapproved difftastic difftool is present"
fi

if rg -q 'GuestEnabled|WindowManager|EnableStandardClickToShowDesktop|GloballyEnabled' "$MACOS_DEFAULTS"; then
  fail "unapproved G4 macOS defaults are present"
fi

printf 'rig-ecosystem-assurance: ok\n'
