#!/usr/bin/env bash
# Deterministic IINA QoL desired-state checks; never writes live IINA/Hammerspoon.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_ROOT="${IINA_QOL_HOME_ROOT:-$ROOT/rig/home}"
HS_DIR="$HOME_ROOT/dot_hammerspoon"
IINA_SUPPORT="$HOME_ROOT/Library/Application Support/com.colliderli.iina"
PLUGIN="$IINA_SUPPORT/plugins/IINA-QoL.iinaplugin"
CONF="$IINA_SUPPORT/input_conf/IINA-QoL.conf"
ZOOM_PY="$ROOT/checks/iina_zoom.py"
INFO_JSON="$PLUGIN/Info.json"

fail=0

fail_msg() {
  printf 'iina-config: %s\n' "$*" >&2
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

require_chezmoiignore() {
  local ignore="$ROOT/rig/home/.chezmoiignore"
  require_file "$ignore" || return 0
  local needle
  for needle in \
    'Library/Application Support/com.colliderli.iina/plugins/.data' \
    'Library/Application Support/com.colliderli.iina/plugins/.preferences' \
    'Library/Application Support/com.colliderli.iina/history.plist' \
    'Library/Application Support/com.colliderli.iina/watch_later' \
    'Library/Application Support/com.colliderli.iina/screenshots'; do
    if ! rg -qxF -- "$needle" "$ignore"; then
      fail_msg "chezmoiignore must list dest path ${needle}"
    fi
  done
}

require_canonical_hs_markers() {
  local init="$HS_DIR/init.lua"
  if [[ ! -f "$init" ]]; then
    return 0
  fi
  if [[ "$HS_DIR" == "$ROOT/rig/home/dot_hammerspoon" ]]; then
    if ! rg -qxF -- '-- >>> IINA QOL >>>' "$init" || ! rg -qxF -- '-- <<< IINA QOL <<<' "$init"; then
      fail_msg 'tracked init.lua must use canonical IINA QOL markers'
    fi
  fi
}

hs_lua_files=()
collect_hs_lua() {
  hs_lua_files=()
  if [[ ! -d "$HS_DIR" ]]; then
    return 0
  fi
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    hs_lua_files+=("$f")
  done < <(find "$HS_DIR" -type f -name '*.lua' | LC_ALL=C sort)
}

require_hs_layout() {
  require_file "$HS_DIR/init.lua" || true
  require_file "$HS_DIR/iina_qol.lua" || true
  if [[ -d "$HS_DIR/iina_qol" ]]; then
    require_file "$HS_DIR/iina_qol/gesture.lua" || true
    require_file "$HS_DIR/iina_qol/window.lua" || true
  else
    require_file "$HS_DIR/iina_qol_gesture.lua" || true
    require_file "$HS_DIR/iina_qol_window.lua" || true
  fi
}

validate_info_json() {
  local path="$1"
  if command -v python3 >/dev/null 2>&1; then
    if ! python3 - "$path" <<'INFOJSON'; then
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except json.JSONDecodeError as exc:
    print(f"invalid json: {exc}", file=sys.stderr)
    raise SystemExit(1)

errors = []
if data.get("identifier") != "com.wyattowalsh.iina-qol":
    errors.append("identifier must be com.wyattowalsh.iina-qol")
if not str(data.get("version") or "").strip():
    errors.append("version must be present")
if data.get("permissions") != ["show-osd"]:
    errors.append("permissions must be exactly [\"show-osd\"]")
if errors:
    print("; ".join(errors), file=sys.stderr)
    raise SystemExit(1)
INFOJSON
      fail_msg "Info.json schema/permissions check failed"
    fi
    return
  fi

  if ! rg -q '"identifier"[[:space:]]*:[[:space:]]*"com.wyattowalsh.iina-qol"' "$path"; then
    fail_msg 'Info.json identifier must be com.wyattowalsh.iina-qol'
  fi
  if ! rg -q '"version"[[:space:]]*:' "$path"; then
    fail_msg 'Info.json version must be present'
  fi
  if ! rg -U -q '"permissions"[[:space:]]*:[[:space:]]*\[[[:space:]]*"show-osd"[[:space:]]*\]' "$path"; then
    fail_msg 'Info.json permissions must be exactly show-osd'
  fi
}

require_conf_needles() {
  if ! rg -q 'seek[[:space:]]+-10' "$CONF"; then
    fail_msg 'IINA-QoL.conf must contain seek -10'
  fi
  if ! rg -q 'seek[[:space:]]+10([^0-9]|$)' "$CONF"; then
    fail_msg 'IINA-QoL.conf must contain seek 10'
  fi
  local needle
  for needle in 'relative+exact' 'relative+keyframes' 'screenshot video' 'ab-loop'; do
    if ! rg -F -q "$needle" "$CONF"; then
      fail_msg "IINA-QoL.conf must contain ${needle}"
    fi
  done

  if ! rg -q '^[[:space:]]*1[[:space:]]+ignore([[:space:]]|$)' "$CONF"; then
    fail_msg 'IINA-QoL.conf must ignore image-adjust key 1'
  fi
  if ! rg -q '^[[:space:]]*F17[[:space:]]+ignore([[:space:]]|$)' "$CONF"; then
    fail_msg 'IINA-QoL.conf must ignore F17 (no center-zoom fallback)'
  fi

  if ! rg -q '^[[:space:]]*q[[:space:]]+ignore([[:space:]]|$)' "$CONF"; then
    fail_msg 'IINA-QoL.conf must ignore q'
  fi
  if ! rg -q '^[[:space:]]*Alt\+s[[:space:]]+ignore([[:space:]]|$)' "$CONF"; then
    fail_msg 'IINA-QoL.conf must ignore Alt+s'
  fi
  if ! rg -q '^[[:space:]]*Ctrl\+h[[:space:]]+ignore([[:space:]]|$)' "$CONF"; then
    fail_msg 'IINA-QoL.conf must ignore Ctrl+h'
  fi

  if rg -q '(^|[[:space:]])(add|set)[[:space:]]+video-zoom([[:space:]]|$)' "$CONF"; then
    fail_msg 'IINA-QoL.conf must not contain add/set video-zoom (no center-zoom fallback)'
  fi
}

require_hs_contracts() {
  if [[ "${#hs_lua_files[@]}" -eq 0 ]]; then
    fail_msg 'Hammerspoon lua files are missing'
    return 0
  fi

  if ! rg -q 'DEFAULT_TAP_ENABLED[[:space:]]*=[[:space:]]*true|tapEnabled[[:space:]]*=[[:space:]]*true' "${hs_lua_files[@]}"; then
    fail_msg 'Hammerspoon sources must default tap on (DEFAULT_TAP_ENABLED / tapEnabled = true)'
  fi

  if ! rg -q -i -e 'cmd[+[:space:]_-]*shift' -e 'shift[+[:space:]_-]*cmd' -e 'command[+[:space:]_-]*shift' "${hs_lua_files[@]}"; then
    fail_msg 'Hammerspoon sources must require cmd+shift (must not consume unmodified scroll)'
  fi
}

run_node_checks() {
  if ! command -v node >/dev/null 2>&1; then
    printf 'iina-config: node unavailable; JS syntax/require checks skipped\n'
    return 0
  fi
  if [[ -f "$PLUGIN/main.js" ]] && ! node --check "$PLUGIN/main.js"; then
    fail_msg 'node --check failed for plugin main.js'
  fi
  if [[ -f "$PLUGIN/lib/zoom.js" ]]; then
    if ! node --check "$PLUGIN/lib/zoom.js"; then
      fail_msg 'node --check failed for lib/zoom.js'
    elif ! (
      cd "$PLUGIN"
      node -e "const z=require('./lib/zoom.js'); const d={w:1920,h:1080,ml:0,mr:0,mt:0,mb:0}; if (z.cursorIsUsable({x:10,y:10}, d)) process.exit(2); if (!z.cursorIsUsable({x:10,y:10,hover:true}, d)) process.exit(3); if (z.cursorIsUsable({x:10,y:10,hover:false}, d)) process.exit(4); const n=z.stepZoom(Math.log2(1.10), -1, {minZoomPercent:100,maxZoomPercent:1000,detentPercent:105}); if (Math.abs(z.percentFromLog2(n)-100)>1e-6) process.exit(5); const L=z.alignAfterZoom(0,0.5,0,0,{x:200,y:200,hover:true},d); const R=z.alignAfterZoom(0,0.5,0,0,{x:1720,y:200,hover:true},d); if (!(L&&R&&L.alignX<0&&R.alignX>0)) process.exit(6); if (z.alignAfterZoom(0,0,0,0,{x:10,y:10,hover:true},d)!==null) process.exit(7); if (z.cursorIsUsable({x:0,y:0,hover:true}, d)) process.exit(8);"
    ); then
      fail_msg 'node require lib/zoom.js hover/detent smoke failed'
    fi
  fi
  if [[ -f "$PLUGIN/lib/settings.js" ]] && ! node --check "$PLUGIN/lib/settings.js"; then
    fail_msg 'node --check failed for lib/settings.js'
  fi
}

run_luac_checks() {
  local path
  if ! command -v luac >/dev/null 2>&1; then
    printf 'iina-config: luac unavailable; Hammerspoon syntax checks skipped\n'
    return 0
  fi
  for path in "${hs_lua_files[@]}"; do
    if ! luac -p "$path"; then
      fail_msg "luac -p failed for ${path#"$ROOT"/}"
    fi
  done
}

run_zoom_self_test() {
  if [[ ! -f "$ZOOM_PY" ]]; then
    return 0
  fi
  if command -v uv >/dev/null 2>&1; then
    if ! uv run python "$ZOOM_PY" --self-test; then
      fail_msg 'iina_zoom.py --self-test failed'
    fi
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    if ! python3 "$ZOOM_PY" --self-test; then
      fail_msg 'iina_zoom.py --self-test failed'
    fi
    return 0
  fi
  printf 'iina-config: python3/uv unavailable; zoom self-test skipped\n'
}

require_file "$INFO_JSON" || true
require_file "$PLUGIN/main.js" || true
require_file "$PLUGIN/lib/zoom.js" || true
require_file "$PLUGIN/lib/settings.js" || true
require_file "$CONF" || true
require_hs_layout
collect_hs_lua

if [[ -f "$INFO_JSON" ]]; then
  validate_info_json "$INFO_JSON"
fi

if [[ -d "$PLUGIN" ]] && rg -F -q -e createServer -e WebSocket "$PLUGIN"; then
  fail_msg 'plugin must not mention createServer/WebSocket'
fi

if [[ -f "$CONF" ]]; then
  require_conf_needles
fi

if [[ -d "$HS_DIR" ]]; then
  require_hs_contracts
  run_luac_checks
fi

run_node_checks
run_zoom_self_test
require_chezmoiignore
require_canonical_hs_markers

if [[ "$fail" -ne 0 ]]; then
  printf 'iina-config: FAIL\n' >&2
  exit 1
fi

printf 'iina-config: ok\n'
