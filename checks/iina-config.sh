#!/usr/bin/env bash
# Static native IINA configuration contracts; never writes live state.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_ROOT="${IINA_NATIVE_SOURCE:-$ROOT/rig/home}"
SUPPORT="$HOME_ROOT/Library/Application Support/com.colliderli.iina"
PROFILE="$SUPPORT/input_conf/IINA-Native.conf"
MPV="$HOME_ROOT/private_dot_config/iina-mpv/mpv.conf"
SHADER_PIN="$HOME_ROOT/private_dot_config/iina-mpv/shaders-pin.json"
OFFICIAL_PIN="$SUPPORT/official-plugins-pin.json"
IGNORE="$ROOT/rig/home/.chezmoiignore"
DEFAULTS="$ROOT/rig/darwin/modules/macos-defaults.nix"
RUNNER="$ROOT/checks/iina-native.sh"
fail=0

bad() {
  printf 'iina-config: %s\n' "$*" >&2
  fail=1
}
require() { [[ -f "$1" ]] || bad "missing $1"; }
for path in "$PROFILE" "$MPV" "$SHADER_PIN" "$OFFICIAL_PIN" "$IGNORE" "$DEFAULTS" "$RUNNER" "$ROOT/checks/iina-shaders.sh" "$ROOT/checks/iina-plugins.sh"; do
  require "$path"
done

if [[ -e "$SUPPORT/input_conf/IINA-QoL.conf" ]]; then
  bad 'retired QoL input profile source must be absent'
fi
if [[ -d "$SUPPORT/plugins/IINA-QoL.iinaplugin" ]] && [[ -n "$(find "$SUPPORT/plugins/IINA-QoL.iinaplugin" -type f -print -quit)" ]]; then
  bad 'retired custom QoL plugin source must be absent'
fi
if [[ -d "$HOME_ROOT/dot_hammerspoon" ]] && [[ -n "$(find "$HOME_ROOT/dot_hammerspoon" -type f \( -name 'iina_qol*' -o -name 'init.lua' \) -print -quit)" ]]; then
  bad 'retired QoL Hammerspoon bridge source must be absent'
fi

if [[ -f "$PROFILE" ]]; then
  for needle in 'seek -10' 'relative+exact' 'screenshot video' 'ab-loop' 'show-text' 'playlist-shuffle' 'WHEEL_UP' 'video-pan-y' 'change-list glsl-shaders clr' 'FSRCNNX_x2_16-0-4-1.glsl' 'Anime4K_Restore_CNN_M.glsl'; do
    rg -F -q "$needle" "$PROFILE" || bad "native profile missing $needle"
  done
  for key in q Alt+s Ctrl+h 1; do
    rg -q "^[[:space:]]*${key//+/\\+}[[:space:]]+ignore([[:space:]]|$)" "$PROFILE" || bad "native profile must ignore $key"
  done
  if rg -q '^[[:space:]]*F(15|16|17|18|19|20)[[:space:]]|iina_qol|IINA-QoL|plugin zoom|Cmd\+scroll zooms' "$PROFILE"; then
    bad 'native profile retains custom QoL/bridge dependency'
  fi
fi
if [[ -f "$MPV" ]] && rg -q '^[[:space:]]*(glsl-shader|glsl-shaders|script)[[:space:]]*=' "$MPV"; then
  bad 'mpv.conf must not force shaders or scripts globally'
fi
if [[ -f "$DEFAULTS" ]]; then
  for needle in 'currentInputConfigName = "IINA-Native";' 'horizontalScrollAction = 3;' 'verticalScrollAction = 3;' 'middleClickAction = 0;'; do
    rg -F -q "$needle" "$DEFAULTS" || bad "nix defaults missing $needle"
  done
fi
if [[ -f "$RUNNER" ]]; then
  for needle in 'currentInputConfigName' 'IINA-Native' 'iina-native-v2'; do
    rg -F -q "$needle" "$RUNNER" || bad "native runner missing $needle"
  done
  bash -n "$RUNNER" || bad 'native runner has invalid bash syntax'
fi
if [[ -f "$IGNORE" ]]; then
  for needle in '.config/iina-mpv/AGENTS.md' '.config/iina-mpv/shaders' 'Library/Application Support/com.colliderli.iina/official-plugins-pin.json' 'Library/Application Support/com.colliderli.iina/plugins/.data' 'Library/Application Support/com.colliderli.iina/plugins/.preferences' 'Library/Application Support/com.colliderli.iina/history.plist' 'Library/Application Support/com.colliderli.iina/watch_later' 'Library/Application Support/com.colliderli.iina/screenshots'; do
    rg -qxF -- "$needle" "$IGNORE" || bad "chezmoiignore must list dest path $needle"
  done
fi

if [[ -f "$PROFILE" && -f "$SHADER_PIN" ]]; then
  if ! uv run python - "$PROFILE" "$SHADER_PIN" <<'PY'
import json
import re
import sys
from pathlib import Path

profile = Path(sys.argv[1]).read_text()
pin = json.loads(Path(sys.argv[2]).read_text())
assert isinstance(pin, dict) and pin.get("version") == 1
pinned = set()
for source in pin["sources"]:
    for item in source["files"] if source["id"] == "anime4k" else source["assets"]:
        pinned.add(item["name"])
referenced = set(re.findall(r"~~/shaders/([A-Za-z0-9_.-]+\.glsl)", profile))
assert referenced and referenced == pinned, f"shader refs: missing={referenced - pinned}, unused={pinned - referenced}"
PY
  then
    bad 'native profile shader bindings do not match pin'
  fi
fi

if [[ -f "$SHADER_PIN" ]] && ! IINA_SHADERS_PIN="$SHADER_PIN" IINA_SHADERS_DEST_ROOT="$HOME_ROOT/private_dot_config/iina-mpv/.check-dest" "$ROOT/checks/iina-shaders.sh" preview >/dev/null; then
  bad 'shader installer preview/pin failed'
fi
if [[ -f "$OFFICIAL_PIN" ]] && ! IINA_PLUGINS_PIN="$OFFICIAL_PIN" IINA_PLUGINS_DEST="$SUPPORT/.check-plugins" "$ROOT/checks/iina-plugins.sh" preview >/dev/null; then
  bad 'official plugin installer preview/pin failed'
fi
[[ "$fail" -eq 0 ]] || {
  printf 'iina-config: FAIL\n' >&2
  exit 1
}
printf 'iina-config: ok\n'
