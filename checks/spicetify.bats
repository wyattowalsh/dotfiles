#!/usr/bin/env bats
# Offline Spotify pin + Spicetify apply checks (no live Spotify/launchctl writes).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/spicetify-bats.XXXXXX")"
  DEST_HOME="$SANDBOX/dest_home"
  mkdir -p "$DEST_HOME/.local/bin" "$DEST_HOME/Library/LaunchAgents" "$DEST_HOME/Library/Logs/spicetify"
}

teardown() {
  rm -rf "$SANDBOX"
}

@test "spicetify static contract passes" {
  run "$REPO_ROOT/checks/spicetify.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spicetify: ok"* ]]
}

@test "spicetify-apply preview does not mutate dest home" {
  export HOME="$DEST_HOME"
  export SPICETIFY_REPO="$REPO_ROOT"
  export SPICETIFY_SPOTIFY_APP="$SANDBOX/Applications/Spotify.app"
  before="$(find "$DEST_HOME" -type f | LC_ALL=C sort | cksum)"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_spicetify-apply" preview
  [ "$status" -eq 0 ]
  after="$(find "$DEST_HOME" -type f | LC_ALL=C sort | cksum)"
  [ "$before" = "$after" ]
  [[ "$output" == *"pin-version 1.2.96.518"* ]]
}

@test "spicetify-apply apply --dry-run does not write Spotify.app" {
  export HOME="$DEST_HOME"
  export SPICETIFY_REPO="$REPO_ROOT"
  export SPICETIFY_SPOTIFY_APP="$SANDBOX/Applications/Spotify.app"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_spicetify-apply" apply --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  [ ! -e "$SANDBOX/Applications/Spotify.app" ]
}

@test "spicetify-apply install --dry-run does not bootstrap launchd" {
  export HOME="$DEST_HOME"
  export SPICETIFY_REPO="$REPO_ROOT"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_spicetify-apply" install --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run: would bootstrap"* ]]
  [[ "$output" == *"would render dest plist"* ]]
  [ ! -f "$DEST_HOME/Library/LaunchAgents/com.wyattowalsh.spicetify-apply.plist" ]
}

@test "freshen skip-casks lists spotify" {
  run rg -qx -- 'spotify' "$REPO_ROOT/rig/home/private_dot_config/freshen/skip-casks"
  [ "$status" -eq 0 ]
}

@test "plist watches Spotify.app and invokes apply" {
  run rg -q '/Applications/Spotify.app' "$REPO_ROOT/rig/home/Library/LaunchAgents/com.wyattowalsh.spicetify-apply.plist.tmpl"
  [ "$status" -eq 0 ]
  run rg -q '<string>apply</string>' "$REPO_ROOT/rig/home/Library/LaunchAgents/com.wyattowalsh.spicetify-apply.plist.tmpl"
  [ "$status" -eq 0 ]
}
