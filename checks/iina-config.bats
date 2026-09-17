#!/usr/bin/env bats
# Offline IINA QoL config + preview checks (no live IINA/Hammerspoon writes).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/iina-qol-bats.XXXXXX")"
  HOME_SRC="$SANDBOX/home_src"
  DEST_HOME="$SANDBOX/dest_home"
  mkdir -p "$HOME_SRC" "$DEST_HOME/.hammerspoon"
  cp -R "$REPO_ROOT/checks/fixtures/iina-qol/valid/." "$HOME_SRC/"
  cat >"$HOME_SRC/dot_hammerspoon/iina_qol_contract.lua" <<'LUA'
DEFAULT_TAP_ENABLED = true
-- consume Command scroll (Shift optional)
LUA
  printf 'untouched\n' >"$DEST_HOME/.hammerspoon/sentinel"
}

teardown() {
  rm -rf "$SANDBOX"
}

snapshot_dest() {
  (
    cd "$DEST_HOME"
    find . -type f | LC_ALL=C sort | while IFS= read -r f; do
      cksum "$f"
    done
  )
}

@test "iina-config accepts a valid fixture tree" {
  export IINA_QOL_HOME_ROOT="$HOME_SRC"
  run "$REPO_ROOT/checks/iina-config.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"iina-config: ok"* ]]
}

@test "iina-qol preview exits 0 and does not modify dest" {
  export HOME="$DEST_HOME"
  export REPO="$REPO_ROOT"
  export IINA_QOL_HOME_ROOT="$HOME_SRC"
  export IINA_QOL_SKIP_DEFAULTS=1
  export IINA_QOL_STATE="$SANDBOX/state"
  before="$(snapshot_dest)"
  run "$REPO_ROOT/checks/iina-qol.sh" preview
  [ "$status" -eq 0 ]
  after="$(snapshot_dest)"
  [ "$before" = "$after" ]
  [ ! -f "$DEST_HOME/.hammerspoon/init.lua" ]
}

@test "iina-qol apply without --apply does not modify dest" {
  export HOME="$DEST_HOME"
  export REPO="$REPO_ROOT"
  export IINA_QOL_HOME_ROOT="$HOME_SRC"
  export IINA_QOL_SKIP_DEFAULTS=1
  export IINA_QOL_STATE="$SANDBOX/state"
  before="$(snapshot_dest)"
  run "$REPO_ROOT/checks/iina-qol.sh" apply
  [ "$status" -eq 0 ]
  after="$(snapshot_dest)"
  [ "$before" = "$after" ]
  [[ "$output" == *"dry-run"* ]]
  [ ! -f "$DEST_HOME/.hammerspoon/init.lua" ]
  [ ! -f "$DEST_HOME/.config/iina-mpv/mpv.conf" ]
}

@test "iina-config requires IINA dest ignores in chezmoiignore" {
  run rg -qxF -- 'Library/Application Support/com.colliderli.iina/history.plist' "$REPO_ROOT/rig/home/.chezmoiignore"
  [ "$status" -eq 0 ]
  run rg -qxF -- 'Library/Application Support/com.colliderli.iina/plugins/.data' "$REPO_ROOT/rig/home/.chezmoiignore"
  [ "$status" -eq 0 ]
  run rg -qxF -- 'Library/Application Support/com.colliderli.iina/screenshots' "$REPO_ROOT/rig/home/.chezmoiignore"
  [ "$status" -eq 0 ]
}

@test "iina-qol apply --apply succeeds when dest init is fully marked" {
  export HOME="$DEST_HOME"
  export REPO="$REPO_ROOT"
  export IINA_QOL_HOME_ROOT="$HOME_SRC"
  export IINA_QOL_SKIP_DEFAULTS=1
  export IINA_QOL_STATE="$SANDBOX/state"
  mkdir -p "$DEST_HOME/.hammerspoon"
  cp "$HOME_SRC/dot_hammerspoon/init.lua" "$DEST_HOME/.hammerspoon/init.lua"
  run "$REPO_ROOT/checks/iina-qol.sh" apply --apply
  [ "$status" -eq 0 ]
  [ -f "$DEST_HOME/.hammerspoon/init.lua" ]
  [ -f "$DEST_HOME/.hammerspoon/sentinel" ]
  [ -f "$DEST_HOME/.config/iina-mpv/mpv.conf" ]
  [ -f "$DEST_HOME/.config/iina-mpv/shaders-pin.json" ]
}

@test "iina-qol apply --apply aborts on unmarked dest init content" {
  export HOME="$DEST_HOME"
  export REPO="$REPO_ROOT"
  export IINA_QOL_HOME_ROOT="$HOME_SRC"
  export IINA_QOL_SKIP_DEFAULTS=1
  export IINA_QOL_STATE="$SANDBOX/state"
  mkdir -p "$DEST_HOME/.hammerspoon"
  {
    cat "$HOME_SRC/dot_hammerspoon/init.lua"
    printf '%s\n' 'hs.alert("keep me")'
  } >"$DEST_HOME/.hammerspoon/init.lua"
  run "$REPO_ROOT/checks/iina-qol.sh" apply --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"refuse apply"* ]]
  [[ "$(cat "$DEST_HOME/.hammerspoon/sentinel")" == "untouched" ]]
}

@test "iina-qol apply --apply prunes the legacy scroll-zoom conf with backup" {
  export HOME="$DEST_HOME"
  export REPO="$REPO_ROOT"
  export IINA_QOL_HOME_ROOT="$HOME_SRC"
  export IINA_QOL_SKIP_DEFAULTS=1
  export IINA_QOL_STATE="$SANDBOX/state"
  mkdir -p "$DEST_HOME/.hammerspoon" "$DEST_HOME/Library/Application Support/com.colliderli.iina/input_conf"
  cp "$HOME_SRC/dot_hammerspoon/init.lua" "$DEST_HOME/.hammerspoon/init.lua"
  printf 'legacy scroll zoom profile\n' >"$DEST_HOME/Library/Application Support/com.colliderli.iina/input_conf/IINA QoL Scroll Zoom.conf"
  run "$REPO_ROOT/checks/iina-qol.sh" apply --apply
  [ "$status" -eq 0 ]
  [ ! -e "$DEST_HOME/Library/Application Support/com.colliderli.iina/input_conf/IINA QoL Scroll Zoom.conf" ]
  [ -f "$SANDBOX/state"/*/iina/input_conf/"IINA QoL Scroll Zoom.conf" ]
  [[ "$(cat "$SANDBOX/state"/*/iina/input_conf/"IINA QoL Scroll Zoom.conf")" == "legacy scroll zoom profile" ]]
}

@test "iina-config rejects a regressed exact-chord Hammerspoon source" {
  BAD_HOME="$SANDBOX/home_bad"
  cp -R "$HOME_SRC" "$BAD_HOME"
  cat >"$BAD_HOME/dot_hammerspoon/iina_qol.lua" <<'LUA'
local M = {}

local tapEnabled = true

local function isExactCmdShift(flags)
  return flags ~= nil and flags.cmd == true and flags.shift == true
end

local function pokePointer()
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.otherMouseDown, {x=0,y=0})
end

return M
LUA
  export IINA_QOL_HOME_ROOT="$BAD_HOME"
  run "$REPO_ROOT/checks/iina-config.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"isZoomChord"* ]]
}

@test "iina shader and official-plugin installers stay dry-run by default" {
  export HOME="$DEST_HOME"
  export IINA_SHADERS_DEST_ROOT="$DEST_HOME/.config/iina-mpv"
  export IINA_SHADERS_STATE="$SANDBOX/shader-state"
  export IINA_PLUGINS_DEST="$DEST_HOME/Library/Application Support/com.colliderli.iina/plugins"
  export IINA_PLUGINS_STATE="$SANDBOX/plugin-state"
  before="$(snapshot_dest)"

  run "$REPO_ROOT/checks/iina-shaders.sh" install
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  run "$REPO_ROOT/checks/iina-plugins.sh" install
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]

  after="$(snapshot_dest)"
  [ "$before" = "$after" ]
  [ ! -e "$DEST_HOME/.config/iina-mpv/shaders" ]
}

@test "iina-config rejects a shader binding missing from the pin" {
  BAD_HOME="$SANDBOX/home_bad_shader"
  cp -R "$HOME_SRC" "$BAD_HOME"
  printf '%s\n' 'Meta+x change-list glsl-shaders set "~~/shaders/NotPinned.glsl"' \
    >>"$BAD_HOME/Library/Application Support/com.colliderli.iina/input_conf/IINA-QoL.conf"
  export IINA_QOL_HOME_ROOT="$BAD_HOME"
  run "$REPO_ROOT/checks/iina-config.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"un-pinned shader"* ]]
}

@test "iina-config accepts the tracked rig/home tree" {
  unset IINA_QOL_HOME_ROOT
  run "$REPO_ROOT/checks/iina-config.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"iina-config: ok"* ]]
}
