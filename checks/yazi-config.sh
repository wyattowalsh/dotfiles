#!/usr/bin/env bash
# Deterministic Yazi desired-state checks; never installs into the live config.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT/rig/home/private_dot_config/yazi"
YAZI_CONFIG="$CONFIG_DIR/yazi.toml"
KEYMAP_CONFIG="$CONFIG_DIR/keymap.toml"
PACKAGE_LOCK="$CONFIG_DIR/package.toml"
THEME_CONFIG="$CONFIG_DIR/theme.toml"
INIT_CONFIG="$CONFIG_DIR/init.lua"

fail=0

fail_msg() {
  printf 'yazi-config: %s\n' "$*" >&2
  fail=1
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    fail_msg "missing ${path#"$ROOT"/}"
    return 1
  fi
  return 0
}

occurrences() {
  local path="$1"
  local needle="$2"
  awk -v needle="$needle" 'index($0, needle) { count++ } END { print count + 0 }' "$path"
}

require_lock() {
  local kind="$1"
  local package="$2"
  local header="[[${kind}.deps]]"
  local stats

  stats="$({
    awk -v header="$header" -v target="$package" '
      function quoted_value(line) {
        sub(/^[^"]*"/, "", line)
        sub(/".*$/, "", line)
        return line
      }

      function finish_block() {
        if (!active || name != target) {
          active = 0
          return
        }

        matches++
        if (length(rev) >= 7 && length(hash) >= 16 && rev !~ /[^0-9a-f]/ && hash !~ /[^0-9a-f]/) {
          valid++
        }
        active = 0
      }

      $0 == header {
        finish_block()
        active = 1
        name = rev = hash = ""
        next
      }

      /^\[\[/ {
        finish_block()
        next
      }

      active && /^[[:space:]]*use[[:space:]]*=/ { name = quoted_value($0); next }
      active && /^[[:space:]]*rev[[:space:]]*=/ { rev = quoted_value($0); next }
      active && /^[[:space:]]*hash[[:space:]]*=/ { hash = quoted_value($0); next }

      END {
        finish_block()
        printf "%d:%d\n", matches, valid
      }
    ' "$PACKAGE_LOCK"
  } 2>/dev/null)"

  if [[ "$stats" != "1:1" ]]; then
    fail_msg "$package must have exactly one resolved $kind lock (found $stats)"
  fi
}

require_binding() {
  local key="$1"
  local command="$2"
  local key_count
  local block

  key_count="$(occurrences "$KEYMAP_CONFIG" "on = \"$key\"")"
  block="$(awk -v key="on = \"$key\"" 'BEGIN { RS = "" } index($0, key) { print }' "$KEYMAP_CONFIG")"

  if [[ "$key_count" != "1" ]]; then
    fail_msg "$key must be bound exactly once (found $key_count)"
  elif ! printf '%s\n' "$block" | rg -F -q "run = \"$command\""; then
    fail_msg "$key must run $command"
  fi
}

for path in "$YAZI_CONFIG" "$KEYMAP_CONFIG" "$PACKAGE_LOCK" "$THEME_CONFIG" "$INIT_CONFIG"; do
  require_file "$path" || true
done

if [[ -f "$YAZI_CONFIG" ]]; then
  if ! rg -q '^\[mgr\]$' "$YAZI_CONFIG"; then
    fail_msg 'yazi.toml must use the current [mgr] table'
  fi
  if rg -q '^\[manager\]$|\{[[:space:]]*name[[:space:]]*=' "$YAZI_CONFIG"; then
    fail_msg 'yazi.toml contains removed manager/name fields'
  fi
  if [[ "$(occurrences "$YAZI_CONFIG" 'url = "*"')" != "1" ]] \
    || [[ "$(occurrences "$YAZI_CONFIG" 'url = "*/"')" != "1" ]] \
    || [[ "$(occurrences "$YAZI_CONFIG" 'group = "git"')" != "2" ]]; then
    fail_msg 'git fetchers must use two current url/group entries'
  fi
  for plugin_ref in 'run = "duckdb"' 'run = "nbpreview"' 'run = "torrent-preview"' "run = 'piper --"; do
    if ! rg -F -q "$plugin_ref" "$YAZI_CONFIG"; then
      fail_msg "yazi.toml missing plugin reference $plugin_ref"
    fi
  done
fi

if [[ -f "$INIT_CONFIG" ]] && ! rg -F -q 'require("git"):setup' "$INIT_CONFIG"; then
  fail_msg 'init.lua must configure the git plugin'
fi

if [[ -f "$KEYMAP_CONFIG" ]]; then
  require_binding '<A-h>' 'plugin duckdb -1'
  require_binding '<A-l>' 'plugin duckdb +1'

  if rg -q '^[[:space:]]*on[[:space:]]*=[[:space:]]*\[[[:space:]]*"g"[[:space:]]*,[[:space:]]*"h"[[:space:]]*\]' "$KEYMAP_CONFIG"; then
    fail_msg 'custom keymap must not override preset g h (Go Home)'
  fi
  if rg -q '^[[:space:]]*on[[:space:]]*=.*"(H|L)"' "$KEYMAP_CONFIG"; then
    fail_msg 'custom keymap must not override preset H/L directory history'
  fi
  if ! rg -F -q 'run = "plugin toggle-pane max-preview"' "$KEYMAP_CONFIG"; then
    fail_msg 'keymap must retain the toggle-pane binding'
  fi
  if ! rg -F -q 'Open with VisiData' "$KEYMAP_CONFIG"; then
    fail_msg 'keymap must include a VisiData opener'
  fi
fi

if [[ -f "$PACKAGE_LOCK" ]]; then
  require_lock plugin 'wylie102/duckdb'
  require_lock plugin 'kirasok/torrent-preview'
  require_lock plugin 'AnirudhG07/nbpreview'
  require_lock plugin 'yazi-rs/plugins:git'
  require_lock plugin 'yazi-rs/plugins:toggle-pane'
  require_lock plugin 'yazi-rs/plugins:piper'
  require_lock flavor 'Mintass/rose-pine'
  require_lock flavor 'Mintass/rose-pine-dawn'
fi

if [[ -f "$THEME_CONFIG" ]]; then
  if [[ "$(occurrences "$THEME_CONFIG" '[flavor]')" != "1" ]] \
    || [[ "$(occurrences "$THEME_CONFIG" 'dark = "rose-pine"')" != "1" ]] \
    || [[ "$(occurrences "$THEME_CONFIG" 'light = "rose-pine-dawn"')" != "1" ]]; then
    fail_msg 'theme.toml must map dark=rose-pine and light=rose-pine-dawn exactly once'
  fi
fi

if [[ "$fail" -ne 0 ]]; then
  printf 'yazi-config: FAIL\n' >&2
  exit 1
fi

if command -v yazi >/dev/null 2>&1 && command -v ya >/dev/null 2>&1; then
  TEST_CONFIG_HOME="$(mktemp -d "${TMPDIR:-/tmp}/yazi-config-check.XXXXXX")"
  trap 'rm -rf "$TEST_CONFIG_HOME"' EXIT
  cp "$CONFIG_DIR"/*.toml "$INIT_CONFIG" "$TEST_CONFIG_HOME/"

  if ! YAZI_CONFIG_HOME="$TEST_CONFIG_HOME" yazi --version >/dev/null; then
    fail_msg 'current Yazi failed to parse the tracked config in an isolated config home'
  fi
  if ! YAZI_CONFIG_HOME="$TEST_CONFIG_HOME" ya pkg list >/dev/null; then
    fail_msg 'current ya failed to parse the tracked package lock in an isolated config home'
  fi
else
  printf 'yazi-config: yazi/ya unavailable; native parse check skipped\n'
fi

if [[ "$fail" -ne 0 ]]; then
  printf 'yazi-config: FAIL\n' >&2
  exit 1
fi

printf 'yazi-config: ok\n'
