#!/usr/bin/env bash
# Static Ghostty source contract plus rendered validation when tools are available.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/rig/home/private_dot_config/ghostty/private_config.tmpl"
DATA="$ROOT/rig/home/.chezmoidata.toml"
ZSHRC="$ROOT/rig/dots/zshrc"
ZSHRC_TEMPLATE="$ROOT/rig/home/dot_zshrc.tmpl"
JUSTFILE="$ROOT/justfile"
PRE_COMMIT="$ROOT/.pre-commit-config.yaml"
HOME_AGENTS="$ROOT/rig/home/AGENTS.md"
TERMINAL_DOCS="$ROOT/docs/content/docs/terminal.mdx"
VALIDATION_DOCS="$ROOT/docs/content/docs/validation.mdx"
HOME_DOCS="$ROOT/docs/content/docs/home-config.mdx"
SHELL_DOCS="$ROOT/docs/content/docs/shell.mdx"

fail=0

fail_msg() {
  printf 'ghostty: %s\n' "$*" >&2
  fail=1
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    fail_msg "missing $path"
    return 1
  fi
  return 0
}

require_line() {
  local path="$1"
  local line="$2"
  local message="$3"
  if ! rg -F -x -q -- "$line" "$path"; then
    fail_msg "$message"
  fi
}

require_text() {
  local path="$1"
  local text="$2"
  local message="$3"
  if ! rg -F -q -- "$text" "$path"; then
    fail_msg "$message"
  fi
}

require_unique_line() {
  local path="$1"
  local line="$2"
  local message="$3"
  local key="${line%% = *}"
  local count assignments
  count="$(rg -F -x -c -- "$line" "$path" || true)"
  assignments="$(rg -c -- "^[[:space:]]*${key}[[:space:]]*=" "$path" || true)"
  if [[ "${count:-0}" != "1" || "${assignments:-0}" != "1" ]]; then
    fail_msg "$message (expected exactly one ${key} assignment)"
  fi
}

reject_line() {
  local path="$1"
  local line="$2"
  local message="$3"
  if rg -F -x -q -- "$line" "$path"; then
    fail_msg "$message"
  fi
}

require_file "$TEMPLATE" || true
require_file "$DATA" || true
require_file "$ZSHRC" || true
require_file "$ZSHRC_TEMPLATE" || true
require_file "$JUSTFILE" || true
require_file "$PRE_COMMIT" || true
require_file "$HOME_AGENTS" || true
require_file "$TERMINAL_DOCS" || true
require_file "$VALIDATION_DOCS" || true
require_file "$HOME_DOCS" || true
require_file "$SHELL_DOCS" || true

if [[ -f "$TEMPLATE" ]]; then
  require_line "$TEMPLATE" '{{- /* chezmoi:template:missing-key=zero */ -}}' \
    "template must retain the missing-key directive"

  overlay_count="$(rg -F -x -c -- 'config-file = ?config.local' "$TEMPLATE" || true)"
  if [[ "${overlay_count:-0}" != "1" ]]; then
    fail_msg "template must contain exactly one optional sibling config.local include"
  fi
  if rg -F -q -- 'config-file = ?{{ .chezmoi.homeDir }}' "$TEMPLATE"; then
    fail_msg "template must not use the legacy absolute config.local include"
  fi
  if rg -q '/Users/' "$TEMPLATE"; then
    fail_msg "template must not hardcode /Users/ paths"
  fi

  for key in theme fontFamily fontSize; do
    require_text "$TEMPLATE" ".ghostty.${key}" "template must reference .ghostty.${key}"
  done

  require_line "$TEMPLATE" 'palette-generate = true' \
    "template must generate the extended palette"
  require_line "$TEMPLATE" 'palette-harmonious = true' \
    "template must harmonize generated colors for the light theme"
  require_unique_line "$TEMPLATE" 'grapheme-width-method = unicode' \
    "template must pin Unicode grapheme widths exactly once"
  require_unique_line "$TEMPLATE" 'window-padding-x = 12' \
    "template must use 12-point horizontal padding exactly once"
  require_unique_line "$TEMPLATE" 'window-padding-y = 10' \
    "template must retain 10-point vertical padding exactly once"
  require_unique_line "$TEMPLATE" 'window-padding-balance = true' \
    "template must balance window padding exactly once"
  require_line "$TEMPLATE" 'shell-integration = detect' \
    "template must let Ghostty detect shell integration"
  require_unique_line "$TEMPLATE" 'macos-titlebar-style = native' \
    "template must use the native macOS titlebar exactly once"
  reject_line "$TEMPLATE" 'macos-titlebar-style = tabs' \
    "custom tabs titlebar is broken on macOS 27 with Ghostty 1.3.1"
  require_unique_line "$TEMPLATE" 'macos-non-native-fullscreen = false' \
    "template must use native fullscreen for tabs exactly once"
  require_unique_line "$TEMPLATE" 'selection-clear-on-copy = false' \
    "template must preserve the selection after copying exactly once"
  require_unique_line "$TEMPLATE" 'copy-on-select = true' \
    "template must set automatic selection copying exactly once (macOS uses the system clipboard)"
  require_unique_line "$TEMPLATE" 'auto-update = off' \
    "template must leave updates to Homebrew exactly once"
  reject_line "$TEMPLATE" 'auto-update = download' \
    "template must not download updates independently of Homebrew"
  if rg -q '^[[:space:]]*auto-update-channel[[:space:]]*=' "$TEMPLATE"; then
    fail_msg "template must not set a channel for the disabled updater"
  fi
  reject_line "$TEMPLATE" 'macos-non-native-fullscreen = padded-notch' \
    "template must not hide tabs in non-native fullscreen"
  require_line "$TEMPLATE" 'keybind = cmd+alt+u=copy_url_to_clipboard' \
    "template must bind Cmd-Option-U to URL copying"
  require_line "$TEMPLATE" 'link-url = true' \
    "template must retain URL detection"
  require_line "$TEMPLATE" 'link-previews = true' \
    "template must retain link previews"
  require_line "$TEMPLATE" 'background-image = {{ .chezmoi.homeDir }}/.config/ghostty/backgrounds/apex-terminal-bg-v3.png' \
    "background image path must use chezmoi.homeDir"
  require_line "$TEMPLATE" 'bell-audio-path = {{ .chezmoi.homeDir }}/.config/ghostty/sounds/notification.aiff' \
    "bell audio path must use chezmoi.homeDir"

  if rg -F -x -q -- 'window-padding-color = extend-background' "$TEMPLATE"; then
    fail_msg "template must not use invalid window-padding-color=extend-background"
  fi
fi

if [[ -f "$DATA" ]]; then
  require_line "$DATA" '[ghostty]' "chezmoi data must contain a [ghostty] table"
  for key in theme fontFamily fontSize; do
    if ! rg -q "^${key}[[:space:]]*=" "$DATA"; then
      fail_msg "chezmoi [ghostty] data must define ${key}"
    fi
  done
fi

for zsh_file in "$ZSHRC" "$ZSHRC_TEMPLATE"; do
  if [[ ! -f "$zsh_file" ]]; then
    continue
  fi
  if rg -F -q -- 'ghostty/shell-integration.zsh' "$zsh_file"; then
    fail_msg "$zsh_file must not source the custom Ghostty shim"
  fi
  if rg -q -- 'GHOSTTY_RESOURCES_DIR|ghostty-integration' "$zsh_file"; then
    fail_msg "$zsh_file must not retain the old Ghostty marker guard"
  fi
  if rg -F -q -- '_ghostty_custom_precmd' "$zsh_file"; then
    fail_msg "$zsh_file must not define the custom OSC-777 hook"
  fi
  require_text "$zsh_file" 'cursor --locate-shell-integration-path zsh' \
    "$zsh_file must retain Cursor shell integration"
done

if [[ -f "$ZSHRC" && -f "$ZSHRC_TEMPLATE" ]] && ! cmp -s "$ZSHRC" "$ZSHRC_TEMPLATE"; then
  fail_msg "zsh runtime and Chezmoi mirror must remain byte-identical"
fi

if [[ -f "$JUSTFILE" ]]; then
  if ! rg -q '^shell_files := ".*checks/ghostty\.sh(?: |")' "$JUSTFILE"; then
    fail_msg "justfile shell_files must include checks/ghostty.sh"
  fi
  require_text "$JUSTFILE" 'check-ghostty:' \
    "justfile must expose check-ghostty"
  require_text "$JUSTFILE" './checks/ghostty.sh' \
    "check-ghostty must execute checks/ghostty.sh"
  if ! rg -q '^check:.*\bcheck-ghostty\b' "$JUSTFILE"; then
    fail_msg "just check must include check-ghostty"
  fi
fi

if [[ -f "$PRE_COMMIT" ]]; then
  require_text "$PRE_COMMIT" 'id: dotfiles-ghostty-config' \
    "pre-commit must define dotfiles-ghostty-config"
  require_text "$PRE_COMMIT" 'entry: just check-ghostty' \
    "pre-commit Ghostty hook must run just check-ghostty"
  require_text "$PRE_COMMIT" 'private_dot_config/ghostty/private_config\.tmpl' \
    "pre-commit must watch the private Ghostty template"
fi

if [[ -f "$HOME_AGENTS" ]]; then
  require_text "$HOME_AGENTS" 'config-file = ?config.local' \
    "rig/home/AGENTS.md must document the sibling-relative overlay"
fi
if [[ -f "$TERMINAL_DOCS" ]]; then
  require_text "$TERMINAL_DOCS" '?config.local' \
    "terminal docs must document the sibling-relative overlay"
  require_text "$TERMINAL_DOCS" 'palette-harmonious' \
    "terminal docs must document harmonious generated palettes"
  require_text "$TERMINAL_DOCS" 'Cmd-Option-U' \
    "terminal docs must document URL copying"
  require_text "$TERMINAL_DOCS" 'macos-titlebar-style = native' \
    "terminal docs must document the native macOS titlebar"
  require_text "$TERMINAL_DOCS" 'macos-non-native-fullscreen = false' \
    "terminal docs must document native fullscreen for tabs"
  require_text "$TERMINAL_DOCS" 'still copies selections to the system clipboard' \
    "terminal docs must state macOS selection writes to the system clipboard"
  if rg -F -q -- 'avoids writing the macOS system clipboard' "$TERMINAL_DOCS" \
    || rg -F -q -- 'prefers the selection clipboard on macOS instead of always copying to the system clipboard' "$TERMINAL_DOCS"; then
    fail_msg "terminal docs must state macOS selection writes to the system clipboard, not the opposite"
  fi
fi
if [[ -f "$VALIDATION_DOCS" ]]; then
  require_text "$VALIDATION_DOCS" 'just check-ghostty' \
    "validation docs must document just check-ghostty"
fi
if [[ -f "$HOME_DOCS" ]]; then
  require_text "$HOME_DOCS" 'config.local' \
    "home-config docs must document the local Ghostty overlay"
fi
if [[ -f "$SHELL_DOCS" ]]; then
  require_text "$SHELL_DOCS" 'gtyv' \
    "shell docs must retain the deployed Ghostty validation alias"
  require_text "$SHELL_DOCS" 'just check-ghostty' \
    "shell docs must distinguish repository Ghostty validation"
fi

if [[ "$fail" -eq 0 ]]; then
  if ! command -v chezmoi >/dev/null 2>&1 || ! command -v ghostty >/dev/null 2>&1; then
    printf 'ghostty: SKIP rendered validation (requires chezmoi and ghostty)\n'
  else
    tmpdir="$(mktemp -d)"
    trap 'rm -rf -- "$tmpdir"' EXIT
    rendered="$tmpdir/config"

    if ! chezmoi --source "$ROOT/rig/home" execute-template --file "$TEMPLATE" >"$rendered"; then
      fail_msg "chezmoi failed to render the tracked Ghostty template"
    else
      if ! rg -F -x -q -- 'config-file = ?config.local' "$rendered"; then
        fail_msg "rendered config must retain the optional sibling overlay"
      fi
      if rg -F -q -- '{{' "$rendered" || rg -F -q -- '}}' "$rendered"; then
        fail_msg "rendered config contains unresolved template expressions"
      fi
      if ! ghostty +validate-config --config-file="$rendered"; then
        fail_msg "Ghostty rejected the rendered base config"
      fi
    fi
  fi
fi

if [[ "$fail" -ne 0 ]]; then
  printf 'ghostty: FAIL\n' >&2
  exit 1
fi

printf 'ghostty: ok\n'
