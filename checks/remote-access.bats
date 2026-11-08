#!/usr/bin/env bats
# Offline remote-access checks (no live launchctl, brew, TCC, or power writes).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/remote-access-bats.XXXXXX")"
  DEST_HOME="$SANDBOX/dest home"
  export MOCK="$SANDBOX/mock-bin"
  STATE="$SANDBOX/state"
  mkdir -p "$DEST_HOME/.local/bin" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk" "$MOCK" "$STATE"
  export HOME="$DEST_HOME"
  export REMOTE_ACCESS_REPO="$REPO_ROOT"
  export REMOTE_ACCESS_STATE_DIR="$STATE"
  export REMOTE_ACCESS_PLIST_ROOT="$SANDBOX/root"
  mkdir -p "$REMOTE_ACCESS_PLIST_ROOT/Library/LaunchDaemons" "$REMOTE_ACCESS_PLIST_ROOT/Library/LaunchAgents"
  export REMOTE_ACCESS_UNAME="Darwin"
  export REMOTE_ACCESS_SKIP_OPEN=1
  export REMOTE_ACCESS_SUDO="$MOCK/sudo"
  export MUTATE_LOG="$SANDBOX/mutate.log"
  : >"$MUTATE_LOG"

  cat >"$MOCK/sudo" <<'EOF'
#!/bin/sh
echo "sudo $*" >>"${MUTATE_LOG}"
case " $* " in
  *"${MOCK_SUDO_FAIL_MATCH:-not-a-command}"*) exit 1 ;;
esac
[ "$1" = '-n' ] && shift
case "$1" in
  launchctl) shift; exec "$MOCK/launchctl" "$@" ;;
  lsof) shift; exec "$MOCK/lsof" "$@" ;;
  /bin/sh)
    "$MOCK/lsof" -nP -iTCP -sTCP:LISTEN -Fpc 2>&1
    result=$?
    printf '\n__REMOTE_ACCESS_LSOF_RC=%s\n' "$result" ;;
  *) exit 0 ;;
esac
EOF
  cat >"$MOCK/brew" <<'EOF'
#!/bin/sh
echo "brew $*" >>"${MUTATE_LOG}"
case "$1 $2 $3" in
  "services start tailscale") echo started; exit 0 ;;
  "install --cask rustdesk") mkdir -p "${HOME}/Applications"; exit 0 ;;
  "install tailscale") exit 0 ;;
esac
exit 0
EOF
  cat >"$MOCK/tailscale" <<'EOF'
#!/bin/sh
echo "tailscale $*" >>"${MUTATE_LOG}"
case "$1" in
  version) echo "1.102.3"; exit 0 ;;
  status)
    if [ "$2" = "--json" ]; then
      if [ -n "${MOCK_TAILSCALE_JSON:-}" ]; then
        /bin/cat "$MOCK_TAILSCALE_JSON"
        exit 0
      fi
      cat <<'JSON'
{"BackendState":"Running","Self":{"Online":true,"HostName":"w4w-mbp","OS":"macOS","TailscaleIPs":["100.64.0.1","fd7a:115c:a1e0::1"]},"CurrentTailnet":{"Name":"test-tailnet.ts.net"},"Peer":{"n":{"ID":"node-default","HostName":"iphone-ww","OS":"iOS","Online":true,"DNSName":"iphone-ww.tailnet.ts.net","TailscaleIPs":["100.64.0.2","fd7a:115c:a1e0::2"]}}}
JSON
      exit 0
    fi
    echo "100.64.0.1 w4w-mbp"
    exit 0
    ;;
  set) exit 0 ;;
  up) exit 0 ;;
esac
exit 0
EOF
  cat >"$MOCK/tailscaled" <<'EOF'
#!/bin/sh
echo "tailscaled $*" >>"${MUTATE_LOG}"
exit 0
EOF
  cat >"$MOCK/launchctl" <<'EOF'
#!/bin/sh
echo "launchctl $*" >>"${MUTATE_LOG}"
[ "$1" = print ] && exit 113
exit 0
EOF
  cat >"$MOCK/lsof" <<'EOF'
#!/bin/sh
exit 1
EOF
  cat >"$MOCK/pgrep" <<'EOF'
#!/bin/sh
exit 1
EOF
  cat >"$MOCK/open" <<'EOF'
#!/bin/sh
echo "open $*" >>"${MUTATE_LOG}"
exit 0
EOF
  cat >"$MOCK/sw_vers" <<'EOF'
#!/bin/sh
echo "ProductVersion: 27.0"
echo "BuildVersion: 26A5425a"
EOF
  cat >"$MOCK/fdesetup" <<'EOF'
#!/bin/sh
echo "FileVault is On."
EOF
  chmod +x "$MOCK"/*
  # Isolate from Homebrew so live tailscale/rg cannot leak into mocks.
  export PATH="$MOCK:/usr/bin:/bin:/usr/sbin:/sbin"
  export REMOTE_ACCESS_PATH="$PATH"
  export REMOTE_ACCESS_TS_WAIT=0
  export REMOTE_ACCESS_LISTEN_WAIT=0
  PRODUCTION_RUNNER="$REPO_ROOT/rig/home/dot_local/bin/executable_remote-access"
  RUNNER="$SANDBOX/legacy-fixture-runner"
  # Preserve historical lifecycle fixtures only inside this mock-root sandbox.
  # Production hold tests invoke PRODUCTION_RUNNER directly; this copy is not
  # evidence that the installed runner can enable, disable, or roll back.
  /usr/bin/perl -0777 -pe 'BEGIN { $n = 0 } $n += s/return 4 # REMOTE_ACCESS_SOURCE_HOLD/return 0 # REMOTE_ACCESS_TEST_FIXTURE/g; END { die "expected one source hold\n" unless $n == 1 }' "$PRODUCTION_RUNNER" >"$RUNNER" || return 1
  chmod 700 "$RUNNER"
}

teardown() {
  rm -rf "$SANDBOX"
}

use_two_peer_fixture() {
  export MOCK_TAILSCALE_JSON="$SANDBOX/two-peers.json"
  cat >"$MOCK_TAILSCALE_JSON" <<'JSON'
{"BackendState":"Running","Self":{"Online":true},"CurrentTailnet":{"Name":"test-tailnet.ts.net"},"Peer":{"one":{"ID":"node-blue","HostName":"iphone-blue","OS":"iOS","Online":true,"DNSName":"iphone-blue.tailnet.test","TailscaleIPs":["100.64.50.2","fd7a:115c:a1e0::2"]},"two":{"ID":"node-green","HostName":"iphone-green","OS":"iOS","Online":true,"DNSName":"iphone-green.tailnet.test","TailscaleIPs":["100.64.50.3","fd7a:115c:a1e0::3"]}}}
JSON
  mkdir -p "$SANDBOX/RustDesk.app/Contents/MacOS"
  printf '#!/bin/sh\nexit 0\n' >"$SANDBOX/RustDesk.app/Contents/MacOS/RustDesk"
  chmod +x "$SANDBOX/RustDesk.app/Contents/MacOS/RustDesk"
  export REMOTE_ACCESS_RD_APP="$SANDBOX/RustDesk.app"
  stateful_vendor_services
}

enabled_fixture() {
  use_two_peer_fixture
  write_fake_password
  "$RUNNER" enable --apply --peer green >"$SANDBOX/fixture-enable.log" 2>&1 || {
    /bin/cat "$SANDBOX/fixture-enable.log" >&2
    return 1
  }
  : >"$MUTATE_LOG"
}

@test "production lifecycle apply is held before any host mutation" {
  stateful_vendor_services
  local agent="$MOCK_ROOT/Library/LaunchAgents/com.carriez.RustDesk_server.plist"
  printf 'operator job B\n' >"$agent"
  : >"$MOCK_LAUNCH_STATE/agent"
  for action in enable disable rollback; do
    : >"$MUTATE_LOG"
    run "$PRODUCTION_RUNNER" "$action" --apply
    [ "$status" -eq 4 ]
    [[ "$output" == *"source-only lifecycle hold"* ]]
    [ ! -s "$MUTATE_LOG" ]
    grep -Fxq 'operator job B' "$agent"
    [ -f "$MOCK_LAUNCH_STATE/agent" ]
  done
}

@test "production rejects multiple subcommands before install side effects" {
  stateful_vendor_services
  for action in enable disable rollback; do
    : >"$MUTATE_LOG"
    run "$PRODUCTION_RUNNER" "$action" --apply install
    [ "$status" -ne 0 ]
    [[ "$output" == *"multiple subcommands are not allowed"* ]]
    [ ! -s "$MUTATE_LOG" ]
    [ ! -e "$DEST_HOME/.local/bin/remote-access" ]
  done
}

@test "production lifecycle hold precedes a stale lock and unreadable journal" {
  mkdir -p "$STATE/lock.d"
  printf 'not-a-pid\n' >"$STATE/lock.d/pid"
  printf '{not-json\n' >"$STATE/state.json"
  run "$PRODUCTION_RUNNER" disable --apply
  [ "$status" -eq 4 ]
  [[ "$output" == *"source-only lifecycle hold"* ]]
  [ -f "$STATE/lock.d/pid" ]
  grep -Fxq '{not-json' "$STATE/state.json"
  [ ! -s "$MUTATE_LOG" ]
}

@test "production hold preserves owned state and loaded label markers" {
  enabled_fixture
  local agent="$MOCK_ROOT/Library/LaunchAgents/com.carriez.RustDesk_server.plist"
  local options="$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  local original_agent original_options original_state
  original_agent="$(/usr/bin/shasum -a 256 "$agent")"
  original_options="$(/usr/bin/shasum -a 256 "$options")"
  original_state="$(/usr/bin/shasum -a 256 "$STATE/state.json")"
  for action in enable disable rollback; do
    : >"$MUTATE_LOG"
    run "$PRODUCTION_RUNNER" "$action" --apply
    [ "$status" -eq 4 ]
    [ ! -s "$MUTATE_LOG" ]
    [ "$(/usr/bin/shasum -a 256 "$agent")" = "$original_agent" ]
    [ "$(/usr/bin/shasum -a 256 "$options")" = "$original_options" ]
    [ "$(/usr/bin/shasum -a 256 "$STATE/state.json")" = "$original_state" ]
    [ -f "$MOCK_LAUNCH_STATE/agent" ]
    [ -f "$MOCK_LAUNCH_STATE/daemon" ]
  done
}

@test "production rollback preserves owned plists for manual adjudication" {
  enabled_fixture
  local daemon="$MOCK_ROOT/Library/LaunchDaemons/com.carriez.RustDesk_service.plist"
  local agent="$MOCK_ROOT/Library/LaunchAgents/com.carriez.RustDesk_server.plist"
  run "$PRODUCTION_RUNNER" rollback --apply
  [ "$status" -eq 4 ]
  [[ "$output" == *"source-only lifecycle hold"* ]]
  [ -f "$daemon" ]
  [ -f "$agent" ]
  ! grep -Fq 'rm -f /Library/Launch' "$MUTATE_LOG"
  ! grep -Fq '"intent": "rolled-back"' "$STATE/state.json"
}

@test "production rollback preserves same-content replacement inode" {
  enabled_fixture
  local agent="$MOCK_ROOT/Library/LaunchAgents/com.carriez.RustDesk_server.plist"
  local replacement="$SANDBOX/operator-agent.plist"
  /bin/cp "$agent" "$replacement"
  /bin/mv "$replacement" "$agent"
  local operator_inode
  operator_inode="$(/usr/bin/stat -f '%i' "$agent")"
  : >"$MUTATE_LOG"
  run "$PRODUCTION_RUNNER" rollback --apply
  [ "$status" -eq 4 ]
  [ "$(/usr/bin/stat -f '%i' "$agent")" = "$operator_inode" ]
  ! grep -Fq 'rm -f /Library/Launch' "$MUTATE_LOG"
  ! grep -Fq '"intent": "rolled-back"' "$STATE/state.json"
}

@test "production doctor refuses loaded jobs without provenance" {
  enabled_fixture
  run "$PRODUCTION_RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"loaded-job identity is unproved"* ]]
}

@test "production off doctor distinguishes no-match from empty successful listener inspection" {
  export REMOTE_ACCESS_RD_APP="$SANDBOX/absent-RustDesk.app"
  local intent result
  printf '%s\n' '[options]' "stop-service = 'Y'" "direct-server = 'N'" >"$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  cat >"$MOCK/lsof" <<'EOF'
#!/bin/sh
exit "$MOCK_EMPTY_LSOF_RC"
EOF
  chmod +x "$MOCK/lsof"
  for intent in disabled rolled-back; do
    printf '{"intent":"%s","journal":{"phase":"steady"}}\n' "$intent" >"$STATE/state.json"
    for result in 0 1; do
      export MOCK_EMPTY_LSOF_RC="$result"
      run "$PRODUCTION_RUNNER" doctor
      if [ "$result" -eq 0 ]; then
        [ "$status" -eq 1 ]
        [[ "$output" == *"listener unknown"* ]]
        [[ "$output" != *"disabled-intent honored"* ]]
      else
        [ "$status" -eq 0 ]
        [[ "$output" == *"disabled-intent honored"* ]]
      fi
    done
  done
}

@test "production off doctor rejects incomplete successful listener records" {
  export REMOTE_ACCESS_RD_APP="$SANDBOX/absent-RustDesk.app"
  local intent records
  printf '%s\n' '[options]' "stop-service = 'Y'" "direct-server = 'N'" >"$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  cat >"$MOCK/lsof" <<'EOF'
#!/bin/sh
if [ "$2" = '-a' ]; then
  printf '%s\n' 'n/usr/bin/other-listener'
else
  printf '%s\n' "$MOCK_LISTENER_RECORDS"
fi
EOF
  chmod +x "$MOCK/lsof"
  for intent in disabled rolled-back; do
    printf '{"intent":"%s","journal":{"phase":"steady"}}\n' "$intent" >"$STATE/state.json"
    for records in 'cOther' 'p123' $'p0\ncOther' $'p123junk\ncOther' $'p123\nc' $'p123\ncOther\ncOther' $'p123\ncOther\np124'; do
      export MOCK_LISTENER_RECORDS="$records"
      run "$PRODUCTION_RUNNER" doctor
      [ "$status" -eq 1 ]
      [[ "$output" == *"listener unknown"* ]]
      [[ "$output" != *"disabled-intent honored"* ]]
    done
  done
}

@test "doctor rejects enabled intent with native stop-service active even when a socket listens" {
  enabled_fixture
  perl -pi -e "s/stop-service = 'N'/stop-service = 'Y'/" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"stop-service"* ]]
}

@test "doctor rejects a spoofed listener owned by a different process" {
  enabled_fixture
  cat >"$MOCK/ps" <<'EOF'
#!/bin/sh
printf '%s\n' '/usr/bin/unrelated-listener --server'
EOF
  chmod +x "$MOCK/ps"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"listener-owner"* ]]
}

@test "doctor rejects a listener with forged RustDesk argv but a different executable" {
  enabled_fixture
  cat >"$MOCK/lsof" <<'EOF'
#!/bin/sh
if [ "$2" = '-a' ]; then
  printf 'p4242\nftxt\nn/usr/bin/unrelated-listener\n'
else
  printf 'p4242\ncRustDesk\n'
fi
EOF
  chmod +x "$MOCK/lsof"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"listener-owner"* ]]
}

@test "doctor reports unknown when listener ownership cannot be inspected" {
  enabled_fixture
  rm "$MOCK/ps"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"listener-owner"* ]]
}

@test "doctor refuses enabled intent when tailscale daemon is down despite a listener" {
  enabled_fixture
  cat >"$MOCK/tailscale" <<'EOF'
#!/bin/sh
if [ "$1" = status ]; then
  printf '%s\n' 'failed to connect to local tailscaled' >&2
  exit 1
fi
exit 0
EOF
  chmod +x "$MOCK/tailscale"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"tailscale-daemon"* ]]
}

@test "doctor refuses enabled intent when JSON backend is stopped despite successful status" {
  enabled_fixture
  export MOCK_TAILSCALE_JSON="$SANDBOX/stopped.json"
  printf '%s\n' '{"BackendState":"Stopped","Self":{"Online":false},"CurrentTailnet":{"Name":"test-tailnet.ts.net"},"Peer":{}}' >"$MOCK_TAILSCALE_JSON"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"tailscale-backend"* ]]
}

@test "doctor refuses enabled intent when tailnet self is offline" {
  enabled_fixture
  export MOCK_TAILSCALE_JSON="$SANDBOX/offline.json"
  printf '%s\n' '{"BackendState":"Running","Self":{"Online":false},"CurrentTailnet":{"Name":"test-tailnet.ts.net"},"Peer":{}}' >"$MOCK_TAILSCALE_JSON"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"tailscale-offline"* ]]
}

@test "doctor accepts matching online named peer and native whitelist as local-only" {
  enabled_fixture
  run "$RUNNER" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"whitelist configured"* ]]
  [[ "$output" == *"not proof of iPhone path"* ]]
  [[ "$output" != *"100.64.50."* ]]
}

@test "enabled doctor rejects a later disabled launchd override despite loaded jobs" {
  enabled_fixture
  : >"$MOCK_LAUNCH_STATE/agent.disabled"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent launchd startup override disabled or unproved"* ]]
}

@test "enabled doctor rejects unquoted exact-label launchd override" {
  enabled_fixture
  : >"$MOCK_LAUNCH_STATE/agent.disabled"
  export MOCK_PRINT_DISABLED_UNQUOTED=1
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent launchd startup override disabled or unproved"* ]]
}

@test "doctor rejects a saved peer missing from current tailnet without leaking addresses" {
  enabled_fixture
  export MOCK_TAILSCALE_JSON="$SANDBOX/stale-peer.json"
  printf '%s\n' '{"BackendState":"Running","Self":{"Online":true},"CurrentTailnet":{"Name":"test-tailnet.ts.net"},"Peer":{"other":{"ID":"node-blue","HostName":"iphone-blue","Online":true,"TailscaleIPs":["100.64.50.2"]}}}' >"$MOCK_TAILSCALE_JSON"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"peer-stale"* ]]
  [[ "$output" != *"100.64.50."* ]]
}

@test "doctor rejects a saved peer that is offline" {
  enabled_fixture
  export MOCK_TAILSCALE_JSON="$SANDBOX/offline-peer.json"
  printf '%s\n' '{"BackendState":"Running","Self":{"Online":true},"CurrentTailnet":{"Name":"test-tailnet.ts.net"},"Peer":{"green":{"ID":"node-green","HostName":"iphone-green","Online":false,"TailscaleIPs":["100.64.50.3","fd7a:115c:a1e0::3"]}}}' >"$MOCK_TAILSCALE_JSON"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"peer-offline"* ]]
  [[ "$output" != *"100.64.50."* ]]
}

@test "doctor fails closed on malformed CurrentTailnet despite healthy backend and listener" {
  enabled_fixture
  export MOCK_TAILSCALE_JSON="$SANDBOX/malformed-tailnet.json"
  printf '%s\n' '{"BackendState":"Running","Self":{"Online":true},"CurrentTailnet":["invalid"],"Peer":{"green":{"ID":"node-green","HostName":"iphone-green","Online":true,"TailscaleIPs":["100.64.50.3","fd7a:115c:a1e0::3"]}}}' >"$MOCK_TAILSCALE_JSON"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"peer-status-unavailable"* ]]
  [[ "$output" != *"100.64.50."* ]]
}

@test "doctor rejects malformed peer addresses without leaking them" {
  enabled_fixture
  export MOCK_TAILSCALE_JSON="$SANDBOX/malformed-addresses.json"
  printf '%s\n' '{"BackendState":"Running","Self":{"Online":true},"CurrentTailnet":{"Name":"test-tailnet.ts.net"},"Peer":{"green":{"ID":"node-green","HostName":"iphone-green","Online":true,"TailscaleIPs":[{"invalid":"100.64.50.3"}]}}}' >"$MOCK_TAILSCALE_JSON"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"whitelist-mismatch"* ]]
  [[ "$output" != *"100.64.50."* ]]
}

@test "doctor rejects an unexpectedly failing peer helper" {
  enabled_fixture
  export MOCK_REAL_PYTHON="$(command -v python3)"
  cat >"$MOCK/python3" <<'EOF'
#!/bin/sh
[ -z "${SAVED_PEER_ID:-}" ] || exit 2
exec "$MOCK_REAL_PYTHON" "$@"
EOF
  chmod +x "$MOCK/python3"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"peer-status-unavailable"* ]]
}

@test "doctor rejects a whitelist that differs from the saved peer live IPs" {
  enabled_fixture
  export MOCK_TAILSCALE_JSON="$SANDBOX/mismatch.json"
  printf '%s\n' '{"BackendState":"Running","Self":{"Online":true},"CurrentTailnet":{"Name":"test-tailnet.ts.net"},"Peer":{"green":{"ID":"node-green","HostName":"iphone-green","Online":true,"TailscaleIPs":["100.64.50.4","fd7a:115c:a1e0::4"]}}}' >"$MOCK_TAILSCALE_JSON"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"whitelist-mismatch"* ]]
  [[ "$output" != *"100.64.50."* ]]
  [[ "$output" != *"fd7a:"* ]]
}

@test "reenable missing password keeps stop-service active and skips vendor autostart" {
  enabled_fixture
  run "$RUNNER" disable --apply
  [ "$status" -eq 0 ]
  rm "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk.toml"
  : >"$MUTATE_LOG"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -eq 4 ]
  grep -Fq "stop-service = 'Y'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  grep -Fq '"intent": "disabled"' "$STATE/state.json"
  if grep -Eq 'sudo launchctl (bootstrap|enable)' "$MUTATE_LOG"; then
    printf '%s\n' 'vendor autostart requested without password' >&2
    return 1
  fi
}

@test "reenable clears the stop-service setting written by disable" {
  enabled_fixture
  run "$RUNNER" disable --apply
  [ "$status" -eq 0 ]
  grep -Fq "stop-service = 'Y'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -eq 0 ]
  grep -Fq "stop-service = 'N'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  if grep -Fq "stop-service = 'Y'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"; then
    printf '%s\n' 'stop-service remains enabled after reenable' >&2
    return 1
  fi
}

@test "remote-access static contract passes" {
  PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" run "$REPO_ROOT/checks/remote-access.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"remote-access: ok"* ]]
}

@test "plan and doctor do not mutate dest home or request elevation" {
  inventory() {
    find "$DEST_HOME" -type f ! -path '*/Library/Caches/*' | LC_ALL=C sort | cksum
  }
  before="$(inventory)"
  run "$RUNNER" plan
  [ "$status" -eq 0 ]
  run "$RUNNER" doctor
  [ "$status" -eq 4 ]
  after="$(inventory)"
  [ "$before" = "$after" ]
  [ ! -f "$DEST_HOME/.local/bin/remote-access" ]
  [ ! -f "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml" ]
  if grep -q 'sudo brew' "$MUTATE_LOG"; then
    echo "doctor/plan requested sudo brew" >&2
    return 1
  fi
}

@test "install --dry-run does not write dest runner or state" {
  run "$RUNNER" install --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  [ ! -f "$DEST_HOME/.local/bin/remote-access" ]
  [ ! -f "$STATE/state.json" ]
  if grep -Eq 'brew install|brew services start' "$MUTATE_LOG"; then
    echo "dry-run mutated brew" >&2
    return 1
  fi
}

@test "enable --dry-run does not install plists or merge config" {
  run "$RUNNER" enable --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  [[ "$output" == *"would not set or rotate a password"* ]]
  [ ! -f "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml" ]
  if grep -q 'LaunchDaemons' "$MUTATE_LOG"; then
    echo "dry-run copied LaunchDaemons" >&2
    return 1
  fi
}

@test "conflicting --dry-run and --apply is rejected" {
  run "$RUNNER" install --dry-run --apply
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot be used together"* ]]
}

@test "password argv and env are refused" {
  run "$RUNNER" enable --apply --password secret
  [ "$status" -ne 0 ]
  [[ "$output" == *"password flags are refused"* ]]
  export REMOTE_ACCESS_PASSWORD=secret
  run "$RUNNER" enable --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"password environment variables are refused"* ]]
  unset REMOTE_ACCESS_PASSWORD
}

@test "repeated install --apply converges without duplicate dest runner copies failing" {
  mkdir -p "$DEST_HOME/Applications/RustDesk.app/Contents/MacOS"
  printf '#!/bin/sh\nexit 0\n' >"$DEST_HOME/Applications/RustDesk.app/Contents/MacOS/RustDesk"
  chmod +x "$DEST_HOME/Applications/RustDesk.app/Contents/MacOS/RustDesk"
  # The runner looks at /Applications/RustDesk.app; install still copies dest runner.
  run "$RUNNER" install --apply
  [ "$status" -eq 0 ]
  run "$RUNNER" install --apply
  [ "$status" -eq 0 ]
  [ -x "$DEST_HOME/.local/bin/remote-access" ]
  run python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$STATE/state.json"
  [ "$status" -eq 0 ]
}

@test "paths with spaces in HOME are safe for dry-run" {
  run "$RUNNER" install --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
}

@test "lock contention is reported" {
  mkdir -p "$STATE/lock.d"
  printf '1\n' >"$STATE/lock.d/pid"
  run "$RUNNER" install --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"another remote-access process"* ]]
}

@test "failed process inspection cannot reclaim a stale-looking lock" {
  mkdir -p "$STATE/lock.d"
  printf '99999999\n' >"$STATE/lock.d/pid"
  cat >"$MOCK/ps" <<'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "$MOCK/ps"
  run "$RUNNER" install --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"owner unknown"* ]]
  [ "$(/bin/cat "$STATE/lock.d/pid")" = 99999999 ]
  [ ! -e "$STATE/lock.d.recovery" ]
  [ ! -e "$STATE/state.json" ]
  [ ! -s "$MUTATE_LOG" ]
}

@test "inspection failure during stale-lock recheck preserves the original lock" {
  mkdir -p "$STATE/lock.d"
  printf '99999999\n' >"$STATE/lock.d/pid"
  export MOCK_PS_CALLS="$SANDBOX/ps-calls"
  printf '0\n' >"$MOCK_PS_CALLS"
  cat >"$MOCK/ps" <<'EOF'
#!/bin/sh
count="$(/bin/cat "$MOCK_PS_CALLS")"
count="$((count + 1))"
printf '%s\n' "$count" >"$MOCK_PS_CALLS"
[ "$count" -lt 2 ] || exit 1
exec /bin/ps "$@"
EOF
  chmod +x "$MOCK/ps"
  run "$RUNNER" install --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"owner unknown"* ]]
  [ "$(/bin/cat "$STATE/lock.d/pid")" = 99999999 ]
  [ ! -e "$STATE/lock.d.recovery" ]
  [ ! -e "$STATE/state.json" ]
}

@test "Linux is unsupported for mutating commands" {
  export REMOTE_ACCESS_UNAME="Linux"
  run "$RUNNER" install --apply
  [ "$status" -eq 3 ]
  [[ "$output" == *"unsupported"* ]]
}

@test "missing tailscale is explicit" {
  rm -f "$MOCK/tailscale" "$MOCK/tailscaled"
  run "$RUNNER" doctor
  echo "$output"
  [ "$status" -eq 4 ]
  [[ "$output" == *"not installed"* || "$output" == *"tailscale-missing"* || "$output" == *"Tailscale variant: not installed"* ]]
}

@test "GUI Tailscale is preserved and brew service is not started" {
  mkdir -p "$SANDBOX/Tailscale.app"
  export REMOTE_ACCESS_TS_APP="$SANDBOX/Tailscale.app"
  : >"$MUTATE_LOG"
  run "$RUNNER" enable --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"preserving GUI Tailscale"* ]]
  if grep -q 'brew services start' "$MUTATE_LOG"; then
    echo "started brew tailscale despite GUI app" >&2
    return 1
  fi
}

@test "ambiguous --peer substring refuses to select an arbitrary phone" {
  use_two_peer_fixture
  run "$RUNNER" enable --apply --peer iphone
  [ "$status" -eq 4 ]
  [ ! -f "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml" ]
  [[ "$output" == *"ambiguous"* ]]
  if grep -q 'sudo launchctl' "$MUTATE_LOG"; then
    echo "ambiguous peer installed vendor services" >&2
    return 1
  fi
}

@test "unique --peer substring selects only its matching phone" {
  use_two_peer_fixture
  write_fake_password
  run "$RUNNER" enable --apply --peer green
  [ "$status" -eq 0 ]
  grep -Fq "whitelist = '100.64.50.3,fd7a:115c:a1e0::3'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  grep -Fq '"hostname": "iphone-green"' "$STATE/state.json"
}

@test "unique named MBP peer stages its macOS addresses for native whitelist readback" {
  use_two_peer_fixture
  export MOCK_TAILSCALE_JSON="$SANDBOX/named-mbp.json"
  printf '%s\n' '{"BackendState":"Running","Self":{"Online":true},"CurrentTailnet":{"Name":"test-tailnet.ts.net"},"Peer":{"phone":{"ID":"node-green","HostName":"iphone-green","OS":"iOS","Online":true,"TailscaleIPs":["100.64.50.3"]},"laptop":{"ID":"node-mbp","HostName":"w4w-mbp","OS":"macOS","Online":true,"DNSName":"w4w-mbp.tailnet.test","TailscaleIPs":["100.64.50.8","fd7a:115c:a1e0::8"]}}}' >"$MOCK_TAILSCALE_JSON"
  write_fake_password
  run "$RUNNER" enable --apply --peer w4w-mbp
  [ "$status" -eq 0 ]
  grep -Fq '"hostname": "w4w-mbp"' "$STATE/state.json"
  grep -Fxq "whitelist = '100.64.50.8,fd7a:115c:a1e0::8'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  grep -Fq '"id": "node-mbp"' "$STATE/state.json"
  grep -Fq '"tailnet": "test-tailnet.ts.net"' "$STATE/state.json"
}

@test "explicitly named offline MBP peer cannot enable or persist its whitelist" {
  use_two_peer_fixture
  export MOCK_TAILSCALE_JSON="$SANDBOX/offline-mbp.json"
  printf '%s\n' '{"BackendState":"Running","Self":{"Online":true},"CurrentTailnet":{"Name":"test-tailnet.ts.net"},"Peer":{"phone":{"ID":"node-green","HostName":"iphone-green","OS":"iOS","Online":true,"TailscaleIPs":["100.64.50.3"]},"laptop":{"ID":"node-mbp","HostName":"w4w-mbp","OS":"macOS","Online":false,"DNSName":"w4w-mbp.tailnet.test","TailscaleIPs":["100.64.50.8"]}}}' >"$MOCK_TAILSCALE_JSON"
  local fake_hash='synthetic-digest'
  printf '%s\n' "password = '${fake_hash}'" >"$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk.toml"
  run "$RUNNER" enable --apply --peer w4w-mbp
  [ "$status" -eq 4 ]
  [ ! -f "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml" ]
  ! grep -Fq '"intent": "enabled"' "$STATE/state.json"
  ! grep -Eq 'sudo launchctl (bootstrap|enable)' "$MUTATE_LOG"
}

@test "ambiguous named matches are rejected even when one matching peer is offline" {
  use_two_peer_fixture
  export MOCK_TAILSCALE_JSON="$SANDBOX/mixed-online.json"
  printf '%s\n' '{"BackendState":"Running","Self":{"Online":true},"CurrentTailnet":{"Name":"test-tailnet.ts.net"},"Peer":{"one":{"ID":"node-blue","HostName":"iphone-blue","OS":"iOS","Online":false,"TailscaleIPs":["100.64.50.2"]},"two":{"ID":"node-green","HostName":"iphone-green","OS":"iOS","Online":true,"TailscaleIPs":["100.64.50.3"]}}}' >"$MOCK_TAILSCALE_JSON"
  run "$RUNNER" enable --apply --peer iphone
  [ "$status" -eq 4 ]
  [[ "$output" == *"ambiguous"* ]]
  [ ! -f "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml" ]
}

@test "reenable refuses disabled intent without native stop-service Y" {
  enabled_fixture
  printf '%s\n' '{"intent":"disabled"}' >"$STATE/state.json"
  : >"$MUTATE_LOG"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -eq 4 ]
  [[ "$output" == *"stop-service"* ]]
  ! grep -Eq 'sudo launchctl (bootstrap|enable)' "$MUTATE_LOG"
  grep -Fq '"intent":"disabled"' "$STATE/state.json"
}

@test "failed vendor plist copy keeps disabled native stop and intent without deleting unowned plists" {
  enabled_fixture
  run "$RUNNER" disable --apply
  [ "$status" -eq 0 ]
  rm "$MOCK_ROOT/Library/LaunchAgents/com.carriez.RustDesk_server.plist"
  export MOCK_SUDO_FAIL_MATCH='set -C; /bin/cat'
  : >"$MUTATE_LOG"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  grep -Fq "stop-service = 'Y'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  grep -Fq '"intent": "disabled"' "$STATE/state.json"
  ! grep -Fq 'sudo rm -f' "$MUTATE_LOG"
}

@test "failed vendor launchctl bootstrap keeps disabled native stop and intent" {
  enabled_fixture
  run "$RUNNER" disable --apply
  [ "$status" -eq 0 ]
  export MOCK_SUDO_FAIL_MATCH='launchctl bootstrap system'
  : >"$MUTATE_LOG"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  grep -Fq "stop-service = 'Y'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  grep -Fq '"intent": "disabled"' "$STATE/state.json"
  ! grep -Fq 'sudo rm -f' "$MUTATE_LOG"
}

@test "first enable failure stages native stop before vendor startup" {
  use_two_peer_fixture
  local fake_hash='synthetic-digest'
  printf '%s\n' "password = '${fake_hash}'" >"$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk.toml"
  export MOCK_SUDO_FAIL_MATCH='launchctl bootstrap system'
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  grep -Fq "stop-service = 'Y'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  ! grep -Fq '"intent": "enabled"' "$STATE/state.json"
  ! grep -Fq 'sudo rm -f' "$MUTATE_LOG"
}

@test "reenable records enabled intent before releasing the native stop" {
  enabled_fixture
  run "$RUNNER" disable --apply
  [ "$status" -eq 0 ]
  export MOCK_REAL_PYTHON="$(command -v python3)"
  cat >"$MOCK/python3" <<'EOF'
#!/bin/sh
if [ -n "${STATE_FILE:-}" ] && [ "$*" = '- --set intent enabled' ]; then
  printf 'intent enabled\n' >>"$MUTATE_LOG"
fi
case " $* " in
  *' --set stop-service N '*) printf 'stop N\n' >>"$MUTATE_LOG" ;;
esac
exec "$MOCK_REAL_PYTHON" "$@"
EOF
  chmod +x "$MOCK/python3"
  : >"$MUTATE_LOG"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -eq 0 ]
  local intent_line stop_line
  intent_line="$(grep -n '^intent enabled$' "$MUTATE_LOG" | cut -d: -f1)"
  stop_line="$(grep -n '^stop N$' "$MUTATE_LOG" | cut -d: -f1)"
  [ "$intent_line" -lt "$stop_line" ]
}

@test "failed release of native stop restores disabled intent after vendor startup" {
  enabled_fixture
  run "$RUNNER" disable --apply
  [ "$status" -eq 0 ]
  export MOCK_REAL_PYTHON="$(command -v python3)"
  cat >"$MOCK/python3" <<'EOF'
#!/bin/sh
case " $* " in
  *' --set stop-service N '*) exit 1 ;;
esac
exec "$MOCK_REAL_PYTHON" "$@"
EOF
  chmod +x "$MOCK/python3"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  grep -Fq "stop-service = 'Y'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  grep -Fq '"intent": "disabled"' "$STATE/state.json"
  ! grep -Fq 'sudo rm -f' "$MUTATE_LOG"
}

@test "toml merge preserves unknown keys and does not write passwords" {
  mkdir -p "$SANDBOX/RustDesk.app/Contents/MacOS"
  printf '#!/bin/sh\nexit 0\n' >"$SANDBOX/RustDesk.app/Contents/MacOS/RustDesk"
  chmod +x "$SANDBOX/RustDesk.app/Contents/MacOS/RustDesk"
  export REMOTE_ACCESS_RD_APP="$SANDBOX/RustDesk.app"
  cp "$REPO_ROOT/checks/fixtures/remote-access/RustDesk2.toml" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  hashed_fixture='hashed-fixture'
  {
    printf "id = 'placeholder-id'\n"
    printf '%s\n' "password=${hashed_fixture}"
    printf "salt = 'not-a-secret-fixture'\n"
  } >"$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk.toml"
  stateful_vendor_services
  run "$RUNNER" enable --apply
  echo "$output"
  [ "$status" -eq 0 ]
  grep -Fq "keep-me = 'yes'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  grep -Fq "direct-server = 'Y'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  grep -Fq "enable-file-transfer = 'N'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  if grep -Ei '^[[:space:]]*password[[:space:]]*=' "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"; then
    echo "password leaked into options toml" >&2
    return 1
  fi
  [[ "$output" != *"--password "* ]]
  [[ "$output" != *"hashed-fixture"* ]]
}

@test "disabled intent survives re-entry of install" {
  run "$RUNNER" install --apply
  [ "$status" -eq 0 ]
  run "$RUNNER" disable --apply
  [ "$status" -eq 0 ]
  run "$RUNNER" install --apply
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("intent",""))' "$STATE/state.json"
  [[ "$output" == *"disabled"* ]]
}

@test "rollback preserves unrelated option keys" {
  mkdir -p "$DEST_HOME/Library/Preferences/com.carriez.RustDesk"
  cp "$REPO_ROOT/checks/fixtures/remote-access/RustDesk2.toml" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  mkdir -p "$STATE/backups"
  cp "$REPO_ROOT/checks/fixtures/remote-access/RustDesk2.toml" "$STATE/backups/RustDesk2.toml.orig"
  python3 - "$STATE/state.json" "$STATE/backups/RustDesk2.toml.orig" <<'PY'
import json, sys
json.dump({"intent": "enabled", "backup": {"toml2": sys.argv[2]}, "owned": {"rustdesk_plists": False}, "peer": {"hostname": "iphone-ww"}}, open(sys.argv[1], "w"), indent=2)
PY
  printf '\noperator-edit = '\''keep'\''\n' >>"$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  run "$RUNNER" rollback --apply
  echo "$output"
  [ "$status" -eq 0 ]
  grep -Fq "keep-me = 'yes'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  grep -Fq "operator-edit = 'keep'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
}

@test "secrets do not appear in dry-run output or generated vendor plists" {
  run "$RUNNER" enable --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"secret"* ]]
  [[ "$output" != *"--password "* ]]
  run "$RUNNER" plan
  [[ "$output" != *"100.64.0.2"* ]]
}

@test "macos bootstrap opt-in is install-only" {
  grep -q 'with-remote-access' "$REPO_ROOT/rig/bootstrap/macos.sh"
  if grep -q 'enable --apply' "$REPO_ROOT/rig/bootstrap/macos.sh"; then
    echo "macos.sh must not call enable --apply" >&2
    return 1
  fi
}

@test "shell startup files do not launch rustdesk or tailscaled" {
  if grep -E -q 'tailscaled|RustDesk|--server' "$REPO_ROOT/rig/dots/zshrc"; then
    echo "zshrc must not start rustdesk/tailscaled" >&2
    return 1
  fi
}

# Adversarial lifecycle fixtures. The simulated root is confined to SANDBOX;
# launchctl marks persist across separate runner invocations, unlike a log-only
# mock. The listener can remain alive when bootout or native stop fails.
stateful_vendor_services() {
  export MOCK_ROOT="$SANDBOX/root"
  export MOCK_LAUNCH_STATE="$SANDBOX/launch-state"
  export REMOTE_ACCESS_PLIST_ROOT="$MOCK_ROOT"
  mkdir -p "$MOCK_ROOT/Library/LaunchDaemons" "$MOCK_ROOT/Library/LaunchAgents" "$MOCK_LAUNCH_STATE"
  cat >"$MOCK/sudo" <<'EOF'
#!/bin/sh
printf 'sudo %s\n' "$*" >>"$MUTATE_LOG"
[ "$1" = '-n' ] && shift
case " $* " in *"${MOCK_SUDO_FAIL_MATCH:-not-a-command}"*) exit 1 ;; esac
case "$1" in
  launchctl) shift; exec "$MOCK/launchctl" "$@" ;;
  lsof) shift; exec "$MOCK/lsof" "$@" ;;
  /bin/sh)
    if [ "${4:-}" = remote-access ]; then
      src="$5"; dest="$6"
      case "$dest" in /Library/*) ;; *) exit 2 ;; esac
      case "$dest" in *"${MOCK_FAIL_COPY_LABEL:-no-such-plist}"*) exit 1 ;; esac
      case "$dest" in *"${MOCK_KILL_ON_COPY_LABEL:-no-such-plist}"*) kill -KILL "$PPID"; exit 1 ;; esac
      mkdir -p "$MOCK_ROOT${dest%/*}"
      case "$dest" in *"${MOCK_RACE_COPY_LABEL:-no-such-plist}"*) /bin/cp "$src" "$MOCK_ROOT$dest" ;; esac
      /bin/sh -c "$3" "$4" "$src" "$MOCK_ROOT$dest" || exit 1
      case "$dest" in *"${MOCK_KILL_AFTER_COPY_LABEL:-no-such-plist}"*) kill -KILL "$PPID"; exit 1 ;; esac
    else
      "$MOCK/lsof" -nP -iTCP -sTCP:LISTEN -Fpc 2>&1
      result=$?
      printf '\n__REMOTE_ACCESS_LSOF_RC=%s\n' "$result"
    fi ;;
  /usr/sbin/chown|/bin/chmod) exit 0 ;;
  rm)
    shift
    [ "$1" = '-f' ] && shift
    for dest do
      case "$dest" in /Library/*) /bin/rm -f "$MOCK_ROOT$dest" ;; *) exit 2 ;; esac
    done ;;
  *) exit 2 ;;
esac
EOF
  cat >"$MOCK/launchctl" <<'EOF'
#!/bin/sh
printf 'launchctl %s\n' "$*" >>"$MUTATE_LOG"
case " $* " in
  *"${MOCK_FAIL_LAUNCH_MATCH:-no-such-command}"*) exit 1 ;;
  *"${MOCK_KILL_LAUNCH_MATCH:-no-such-command}"*) kill -KILL "$PPID"; exit 1 ;;
esac
verb="$1"; target="$2"
case "$target" in
  *com.carriez.RustDesk_service*) unit=daemon ;;
  *com.carriez.RustDesk_server*) unit=agent ;;
  gui/*) unit=agent ;;
  system) unit=daemon ;;
  *) exit 2 ;;
esac
case "$verb" in
  print) [ -f "$MOCK_LAUNCH_STATE/$unit" ] && exit 0 || exit 113 ;;
  print-disabled)
    [ "${MOCK_FAIL_PRINT_DISABLED:-0}" = 1 ] && exit 1
    printf 'disabled services = {\n'
    [ -f "$MOCK_LAUNCH_STATE/$unit.disabled" ] && {
      if [ "$unit" = daemon ]; then label=com.carriez.RustDesk_service
      else label=com.carriez.RustDesk_server; fi
      [ "${MOCK_PRINT_DISABLED_BOOL:-0}" != 1 ] || value=true
      if [ "${MOCK_PRINT_DISABLED_UNQUOTED:-0}" = 1 ]; then
        printf '    %s => %s\n' "$label" "${value:-disabled}"
      else
        printf '    "%s" => %s\n' "$label" "${value:-disabled}"
      fi
    }
    printf '}\n' ;;
  disable)
    [ "${MOCK_FAIL_DISABLE:-0}" != 1 ] || exit 1
    : >"$MOCK_LAUNCH_STATE/$unit.disabled"
    [ "${MOCK_KILL_AFTER_DISABLE:-}" != "$unit" ] || kill -KILL "$PPID" ;;
  bootout)
    [ "${MOCK_FAIL_BOOTOUT:-0}" = 1 ] && exit 1
    /bin/rm -f "$MOCK_LAUNCH_STATE/$unit" ;;
  bootstrap)
    [ "${MOCK_FAIL_BOOTSTRAP:-0}" = 1 ] && exit 1
    [ ! -f "$MOCK_LAUNCH_STATE/$unit.disabled" ] || exit 1
    : >"$MOCK_LAUNCH_STATE/$unit" ;;
  enable) /bin/rm -f "$MOCK_LAUNCH_STATE/$unit.disabled" ;;
  *) exit 2 ;;
esac
EOF
  cat >"$MOCK/ps" <<'EOF'
#!/bin/sh
case " $* " in
  *' -o stat='*) exec /bin/ps "$@" ;;
  *' -p 4242 -o command='*) printf '%s/Contents/MacOS/RustDesk --server\n' "$REMOTE_ACCESS_RD_APP" ;;
  *) exec /bin/ps "$@" ;;
esac
EOF
  cat >"$MOCK/lsof" <<'EOF'
#!/bin/sh
if [ "$2" = '-a' ]; then
  printf 'p4242\nftxt\nn%s/Contents/MacOS/RustDesk\n' "$REMOTE_ACCESS_RD_APP"
  exit 0
fi
if [ "${MOCK_STUBBORN_LISTENER:-0}" != 1 ]; then
  [ -f "$MOCK_LAUNCH_STATE/agent" ] || exit 1
  grep -Fq "stop-service = 'N'" "$HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml" || exit 1
fi
printf 'p4242\ncRustDesk\n'
EOF
  chmod +x "$MOCK/sudo" "$MOCK/launchctl" "$MOCK/lsof" "$MOCK/ps"
}

write_fake_password() {
  local fake_hash='synthetic-digest'
  printf '%s\n' "password = '${fake_hash}'" >"$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk.toml"
}

# Model launchd loading RunAtLoad vendor plists on the next boot/login.
simulate_launchd_reboot() {
  local unit path
  rm -f "$MOCK_LAUNCH_STATE/daemon" "$MOCK_LAUNCH_STATE/agent"
  for unit in daemon agent; do
    if [ "$unit" = daemon ]; then
      path="$MOCK_ROOT/Library/LaunchDaemons/com.carriez.RustDesk_service.plist"
    else
      path="$MOCK_ROOT/Library/LaunchAgents/com.carriez.RustDesk_server.plist"
    fi
    [ ! -f "$path" ] || [ -f "$MOCK_LAUNCH_STATE/$unit.disabled" ] || : >"$MOCK_LAUNCH_STATE/$unit"
  done
}

@test "disable cannot report success if native stop and launchctl bootout both fail" {
  enabled_fixture
  stateful_vendor_services
  : >"$MOCK_LAUNCH_STATE/agent"
  : >"$MOCK_LAUNCH_STATE/daemon"
  export MOCK_FAIL_BOOTOUT=1
  export MOCK_REAL_PYTHON="$(command -v python3)"
  cat >"$MOCK/python3" <<'EOF'
#!/bin/sh
case " $* " in *' --set stop-service Y '*) exit 1 ;; esac
exec "$MOCK_REAL_PYTHON" "$@"
EOF
  chmod +x "$MOCK/python3"
  run "$RUNNER" disable --apply
  [ "$status" -ne 0 ]
  [ -f "$MOCK_LAUNCH_STATE/agent" ]
  grep -Fq '"intent": "enabled"' "$STATE/state.json"
}

@test "disable cannot report success with a listener still alive after bootout" {
  enabled_fixture
  stateful_vendor_services
  : >"$MOCK_LAUNCH_STATE/agent"
  : >"$MOCK_LAUNCH_STATE/daemon"
  export MOCK_FAIL_BOOTOUT=1 MOCK_STUBBORN_LISTENER=1
  run "$RUNNER" disable --apply
  [ "$status" -ne 0 ]
  [ -f "$MOCK_LAUNCH_STATE/agent" ]
  ! grep -Fq '"intent": "disabled"' "$STATE/state.json"
}

@test "disable rejects vendor rewriting native stop after listener probe" {
  enabled_fixture
  cat >"$MOCK/lsof" <<'EOF'
#!/bin/sh
perl -pi -e "s/stop-service = 'Y'/stop-service = 'N'/" "$HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
exit 1
EOF
  chmod +x "$MOCK/lsof"
  run "$RUNNER" disable --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"final native off readback changed"* ]]
  ! grep -Fq '"intent": "disabled"' "$STATE/state.json"
}

@test "disabled doctor fails closed when RustDesk still owns a live listener" {
  enabled_fixture
  stateful_vendor_services
  : >"$MOCK_LAUNCH_STATE/agent"
  printf '%s\n' '{"intent":"disabled"}' >"$STATE/state.json"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"listener"* ]]
}

@test "first-enable plist copy failure leaves no direct-IP access without a prior TOML backup" {
  use_two_peer_fixture
  stateful_vendor_services
  write_fake_password
  export MOCK_FAIL_COPY_LABEL='com.carriez.RustDesk_server'
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  local options="$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  [ -f "$options" ]
  grep -Fq 'sudo /bin/sh -c set -C; /bin/cat' "$MUTATE_LOG"
  if grep -Fq "direct-server = 'Y'" "$options"; then
    printf 'direct-IP access remains enabled after first-enable failure\n' >&2
    return 1
  fi
  grep -Fq "stop-service = 'Y'" "$options"
  if grep -Fq '"intent": "enabled"' "$STATE/state.json"; then
    printf 'failed enable persisted enabled intent\n' >&2
    return 1
  fi
}

@test "failed first-enable launchctl bootstrap cannot leave direct-IP enabled" {
  use_two_peer_fixture
  stateful_vendor_services
  write_fake_password
  export MOCK_FAIL_BOOTSTRAP=1
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  grep -Fq 'launchctl bootstrap system' "$MUTATE_LOG"
  local options="$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  [ -f "$options" ]
  if grep -Fq "direct-server = 'Y'" "$options"; then
    printf 'direct-IP access remains enabled after bootstrap failure\n' >&2
    return 1
  fi
  grep -Fq "stop-service = 'Y'" "$options"
  [ ! -f "$MOCK_LAUNCH_STATE/agent" ]
}

@test "re-entry after interrupted partial plist copy preserves an operator-edited daemon" {
  use_two_peer_fixture
  stateful_vendor_services
  write_fake_password
  local daemon="$MOCK_ROOT/Library/LaunchDaemons/com.carriez.RustDesk_service.plist"
  export MOCK_KILL_ON_COPY_LABEL='com.carriez.RustDesk_server'
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  [ -f "$daemon" ]
  printf 'operator edit after interrupted copy\n' >"$daemon"
  unset MOCK_KILL_ON_COPY_LABEL
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  grep -Fxq 'operator edit after interrupted copy' "$daemon"
}

@test "first enable refuses to overwrite a preexisting unowned vendor plist" {
  use_two_peer_fixture
  stateful_vendor_services
  write_fake_password
  local preexisting="$MOCK_ROOT/Library/LaunchDaemons/com.carriez.RustDesk_service.plist"
  printf 'preexisting operator plist\n' >"$preexisting"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  grep -Fxq 'preexisting operator plist' "$preexisting"
  ! grep -Fq '"intent": "enabled"' "$STATE/state.json"
}

@test "matching plist inserted at exclusive-copy boundary is not claimed or removed" {
  use_two_peer_fixture
  write_fake_password
  export MOCK_RACE_COPY_LABEL='com.carriez.RustDesk_service'
  local daemon="$MOCK_ROOT/Library/LaunchDaemons/com.carriez.RustDesk_service.plist"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  [ -f "$daemon" ]
  ! grep -Fq '"sha"' "$STATE/state.json"
  unset MOCK_RACE_COPY_LABEL
  run "$RUNNER" rollback --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"not fingerprint-owned"* ]]
  [ -f "$daemon" ]
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  [ -f "$daemon" ]
}

@test "copy-then-SIGKILL leaves matching but unclaimed plist untouched on re-entry" {
  use_two_peer_fixture
  write_fake_password
  export MOCK_KILL_AFTER_COPY_LABEL='com.carriez.RustDesk_service'
  local daemon="$MOCK_ROOT/Library/LaunchDaemons/com.carriez.RustDesk_service.plist"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  [ -f "$daemon" ]
  ! grep -Fq '"sha"' "$STATE/state.json"
  unset MOCK_KILL_AFTER_COPY_LABEL
  run "$RUNNER" disable --apply
  [ "$status" -ne 0 ]
  run "$RUNNER" rollback --apply
  [ "$status" -ne 0 ]
  [ -f "$daemon" ]
}

@test "ambiguous lock without pid refuses seizure before any mutation" {
  mkdir "$STATE/lock.d"
  run "$RUNNER" disable --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"owner unknown"* ]]
  [ ! -f "$STATE/state.json" ]
}

@test "corrupt or symlinked journal blocks apply before package or native changes" {
  local bad="$STATE/state.json" options="$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  printf 'not json\n' >"$bad"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  [ ! -e "$options" ]
  [ ! -s "$MUTATE_LOG" ]
  rm "$bad"
  printf '{"intent":"enabled"}\n' >"$SANDBOX/foreign.json"
  ln -s "$SANDBOX/foreign.json" "$bad"
  run "$RUNNER" disable --apply
  [ "$status" -ne 0 ]
  [ ! -e "$options" ]
  [ ! -s "$MUTATE_LOG" ]
}

@test "enabled doctor rejects native direct-IP security option drift" {
  enabled_fixture
  perl -pi -e "s/direct-server = 'Y'/direct-server = 'N'/" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"direct-server"* ]]
}

@test "enabled doctor rejects a replacement node with the same hostname and addresses" {
  enabled_fixture
  # Change only the pinned node ID; keep the real enabled transaction's
  # plist ownership and options journal, or safe-off must rightly refuse.
  perl -pi -e 's/"id": "node-green"/"id": "node-original"/' "$STATE/state.json"
  export MOCK_TAILSCALE_JSON="$SANDBOX/replaced-peer.json"
  printf '%s\n' '{"BackendState":"Running","Self":{"Online":true},"CurrentTailnet":{"Name":"test-tailnet.ts.net"},"Peer":{"replacement":{"ID":"node-replacement","HostName":"iphone-green","OS":"iOS","Online":true,"TailscaleIPs":["100.64.50.3","fd7a:115c:a1e0::3"]}}}' >"$MOCK_TAILSCALE_JSON"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"peer"* ]]
  [[ "$output" != *"100.64.50."* ]]
}

@test "enable refuses to silently rebind a saved peer to a replacement node" {
  enabled_fixture
  # Change only the pinned node ID; keep the real enabled transaction's
  # plist ownership and options journal, or safe-off must rightly refuse.
  perl -pi -e 's/"id": "node-green"/"id": "node-original"/' "$STATE/state.json"
  export MOCK_TAILSCALE_JSON="$SANDBOX/replaced-peer.json"
  printf '%s\n' '{"BackendState":"Running","Self":{"Online":true},"CurrentTailnet":{"Name":"test-tailnet.ts.net"},"Peer":{"replacement":{"ID":"node-replacement","HostName":"iphone-green","OS":"iOS","Online":true,"TailscaleIPs":["100.64.50.3","fd7a:115c:a1e0::3"]}}}' >"$MOCK_TAILSCALE_JSON"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  grep -Fq '"id": "node-original"' "$STATE/state.json"
  grep -Fq '"intent": "disabled"' "$STATE/state.json"
  [ ! -f "$MOCK_LAUNCH_STATE/agent" ]
  grep -Fq "direct-server = 'N'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
}

@test "rollback conflict does not report completion while a listener persists" {
  enabled_fixture
  stateful_vendor_services
  : >"$MOCK_LAUNCH_STATE/agent"
  mkdir -p "$STATE/backups"
  printf '%s\n' '[options]' "whitelist = 'other-node'" >"$STATE/backups/RustDesk2.toml.orig"
  printf '%s\n' '{"intent":"enabled","backup":{"toml2":"'"$STATE"'/backups/RustDesk2.toml.orig"},"owned":{"rustdesk_plists":false},"peer":{"hostname":"iphone-green"}}' >"$STATE/state.json"
  export MOCK_STUBBORN_LISTENER=1
  run "$RUNNER" rollback --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"listener"* ]]
  ! grep -Fq '"intent": "rolled-back"' "$STATE/state.json"
}

@test "native stop failure prevents direct-IP and plist mutations even if bootout succeeds" {
  enabled_fixture
  export MOCK_REAL_PYTHON="$(command -v python3)"
  cat >"$MOCK/python3" <<'EOF'
#!/bin/sh
case " $* " in *' --set stop-service Y '*) exit 1 ;; esac
exec "$MOCK_REAL_PYTHON" "$@"
EOF
  chmod +x "$MOCK/python3"
  : >"$MUTATE_LOG"
  run "$RUNNER" disable --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsafe"* ]]
  ! grep -Eq 'sudo /bin/cp|launchctl bootstrap|launchctl enable' "$MUTATE_LOG"
  grep -Fq '"phase": "unsafe"' "$STATE/state.json"
}

@test "disabled owned jobs stay off across simulated reboot and explicit enable restores them" {
  enabled_fixture
  run "$RUNNER" disable --apply
  [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
  [ -f "$MOCK_ROOT/Library/LaunchDaemons/com.carriez.RustDesk_service.plist" ]
  [ -f "$MOCK_ROOT/Library/LaunchAgents/com.carriez.RustDesk_server.plist" ]
  [ -f "$MOCK_LAUNCH_STATE/daemon.disabled" ]
  [ -f "$MOCK_LAUNCH_STATE/agent.disabled" ]
  simulate_launchd_reboot
  [ ! -f "$MOCK_LAUNCH_STATE/daemon" ]
  [ ! -f "$MOCK_LAUNCH_STATE/agent" ]
  run "$RUNNER" doctor
  [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
  : >"$MUTATE_LOG"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
  [ ! -f "$MOCK_LAUNCH_STATE/daemon.disabled" ]
  [ ! -f "$MOCK_LAUNCH_STATE/agent.disabled" ]
  [ -f "$MOCK_LAUNCH_STATE/daemon" ]
  [ -f "$MOCK_LAUNCH_STATE/agent" ]
  local enable_line bootstrap_line
  enable_line="$(grep -n '^launchctl enable system/' "$MUTATE_LOG" | cut -d: -f1)"
  bootstrap_line="$(grep -n '^launchctl bootstrap system' "$MUTATE_LOG" | cut -d: -f1)"
  [ "$enable_line" -lt "$bootstrap_line" ]
}

@test "disabled doctor rejects missing durable override before and after reboot autoload" {
  enabled_fixture
  run "$RUNNER" disable --apply
  [ "$status" -eq 0 ]
  rm "$MOCK_LAUNCH_STATE/agent.disabled"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent durable disable unproved"* ]]
  simulate_launchd_reboot
  [ -f "$MOCK_LAUNCH_STATE/agent" ]
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor agent"* ]]
}

@test "disabled intent is withheld when launchd durable disable cannot be verified" {
  enabled_fixture
  export MOCK_FAIL_PRINT_DISABLED=1
  run "$RUNNER" disable --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"durable disable unproved"* ]]
  ! grep -Fq '"intent": "disabled"' "$STATE/state.json"
  [ -f "$MOCK_ROOT/Library/LaunchAgents/com.carriez.RustDesk_server.plist" ]
  unset MOCK_FAIL_PRINT_DISABLED
  export MOCK_PRINT_DISABLED_BOOL=1
  run "$RUNNER" disable --apply
  [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
}

@test "operator-disabled launchd label is preserved rather than seized on first enable" {
  use_two_peer_fixture
  write_fake_password
  : >"$MOCK_LAUNCH_STATE/agent.disabled"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  [[ "$output" == *"operator-disabled agent launchd override preserved"* ]]
  [ -f "$MOCK_LAUNCH_STATE/agent.disabled" ]
  [ ! -f "$MOCK_LAUNCH_STATE/agent" ]
  ! grep -Fq 'launchctl enable gui/' "$MUTATE_LOG"
  # The daemon may be disabled by the failed enable's off guard, but the
  # operator-owned agent must never be claimed as ours.
  run python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("launchd",{}).get("agent",{}).get("disabled_by_us"))' "$STATE/state.json"
  [ "$output" != True ]
}

@test "explicit re-enable failure keeps owned override disabled and native stop on" {
  enabled_fixture
  run "$RUNNER" disable --apply
  [ "$status" -eq 0 ]
  export MOCK_FAIL_LAUNCH_MATCH='enable system/'
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  [ -f "$MOCK_LAUNCH_STATE/daemon.disabled" ]
  [ ! -f "$MOCK_LAUNCH_STATE/agent" ]
  grep -Fq '"intent": "disabled"' "$STATE/state.json"
  grep -Fq "stop-service = 'Y'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  unset MOCK_FAIL_LAUNCH_MATCH
  run "$RUNNER" doctor
  [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
}

@test "interrupted disable cannot adopt a launchd override with unknown provenance" {
  enabled_fixture
  export MOCK_KILL_AFTER_DISABLE=daemon
  run "$RUNNER" disable --apply
  [ "$status" -ne 0 ]
  [ -f "$MOCK_LAUNCH_STATE/daemon.disabled" ]
  unset MOCK_KILL_AFTER_DISABLE
  : >"$MUTATE_LOG"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  [ -f "$MOCK_LAUNCH_STATE/daemon.disabled" ]
  ! grep -Fq 'launchctl enable system/' "$MUTATE_LOG"
  ! grep -Fq '"intent": "disabled"' "$STATE/state.json"
}

@test "disable does not persist an override for an unowned unloaded vendor plist" {
  enabled_fixture
  run "$RUNNER" disable --apply
  [ "$status" -eq 0 ]
  local agent="$MOCK_ROOT/Library/LaunchAgents/com.carriez.RustDesk_server.plist"
  printf 'operator replacement\n' >"$agent"
  : >"$MUTATE_LOG"
  run "$RUNNER" disable --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"not fingerprint-owned"* ]]
  ! grep -Fq 'launchctl disable gui/' "$MUTATE_LOG"
  grep -Fxq 'operator replacement' "$agent"
}

@test "disabled doctor rejects loaded launchd job even with no listener" {
  enabled_fixture
  run "$RUNNER" disable --apply
  [ "$status" -eq 0 ]
  : >"$MOCK_LAUNCH_STATE/agent"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor agent"* ]]
}

@test "disable does not bootout or erase an unowned loaded vendor job" {
  enabled_fixture
  local agent="$MOCK_ROOT/Library/LaunchAgents/com.carriez.RustDesk_server.plist"
  printf 'operator job\n' >"$agent"
  : >"$MUTATE_LOG"
  run "$RUNNER" disable --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"not fingerprint-owned"* ]]
  [ -f "$MOCK_LAUNCH_STATE/agent" ]
  grep -Fxq 'operator job' "$agent"
  ! grep -Fq 'launchctl bootout gui/' "$MUTATE_LOG"
  ! grep -Fq 'launchctl disable gui/' "$MUTATE_LOG"
  ! grep -Fq '"intent": "disabled"' "$STATE/state.json"
}

@test "legacy pre-copy digest claims do not authorize bootout or removal" {
  enabled_fixture
  perl -pi -e 's/"created": true/"created": false/g' "$STATE/state.json"
  : >"$MUTATE_LOG"
  run "$RUNNER" disable --apply
  [ "$status" -ne 0 ]
  [ -f "$MOCK_LAUNCH_STATE/agent" ]
  ! grep -Fq 'launchctl bootout gui/' "$MUTATE_LOG"
  local daemon="$MOCK_ROOT/Library/LaunchDaemons/com.carriez.RustDesk_service.plist"
  run "$RUNNER" rollback --apply
  [ "$status" -ne 0 ]
  [ -f "$daemon" ]
}

@test "enabled doctor rejects altered owned plist and absent agent job" {
  enabled_fixture
  printf 'operator edit\n' >>"$MOCK_ROOT/Library/LaunchDaemons/com.carriez.RustDesk_service.plist"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"plist"* ]]
  # A clean owned plist with a stopped job still fails.
  cp "$STATE/daemon.plist" "$MOCK_ROOT/Library/LaunchDaemons/com.carriez.RustDesk_service.plist"
  rm "$MOCK_LAUNCH_STATE/agent"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"launchd"* ]]
}

@test "doctor checks every security-critical managed option" {
  local key value
  for key in enable-file-transfer enable-tunnel enable-terminal allow-remote-config-modification enable-lan-discovery approve-mode verification-method; do
    enabled_fixture
    value="$(grep "^$key = " "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml")"
    perl -pi -e "s/\\Q$value\\E/$key = 'unsafe'/" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
    run "$RUNNER" doctor
    [ "$status" -eq 1 ] || { printf 'unexpected green for %s\n' "$key" >&2; return 1; }
    [[ "$output" == *"$key"* ]] || return 1
    teardown
    setup
  done
}

@test "rollback retains plists and safe-off sentinel when agent is unowned" {
  enabled_fixture
  local daemon="$MOCK_ROOT/Library/LaunchDaemons/com.carriez.RustDesk_service.plist"
  local agent="$MOCK_ROOT/Library/LaunchAgents/com.carriez.RustDesk_server.plist"
  printf 'unowned operator agent\n' >"$agent"
  run "$RUNNER" rollback --apply
  [ "$status" -ne 0 ]
  [ -f "$daemon" ]
  grep -Fxq 'unowned operator agent' "$agent"
  ! grep -Fq '"intent": "rolled-back"' "$STATE/state.json"
  grep -Fq "direct-server = 'N'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
}

@test "rollback with retained plists keeps off sentinel and later unknown edits" {
  enabled_fixture
  local options="$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  printf '%s\n' "operator-edit = 'keep'" >>"$options"
  run "$RUNNER" rollback --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"plist retained for attended review"* ]]
  grep -Fq "operator-edit = 'keep'" "$options"
  grep -Fq "direct-server = 'N'" "$options"
  grep -Fq "stop-service = 'Y'" "$options"
  [ -f "$MOCK_ROOT/Library/LaunchDaemons/com.carriez.RustDesk_service.plist" ]
  [ -f "$MOCK_ROOT/Library/LaunchAgents/com.carriez.RustDesk_server.plist" ]
  ! grep -Fq '"intent": "rolled-back"' "$STATE/state.json"
  simulate_launchd_reboot
  [ ! -f "$MOCK_LAUNCH_STATE/daemon" ]
  [ ! -f "$MOCK_LAUNCH_STATE/agent" ]
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
}

@test "rollback CAS refuses a changed managed whitelist without deleting unowned files" {
  enabled_fixture
  local options="$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  perl -pi -e "s/whitelist = '.*'/whitelist = 'operator-value'/" "$options"
  run "$RUNNER" rollback --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"operator-modified"* ]]
  grep -Fq "whitelist = 'operator-value'" "$options"
  ! grep -Fq '"intent": "rolled-back"' "$STATE/state.json"
}

@test "install re-entry after interrupted arming proves off instead of relabeling a live listener" {
  enabled_fixture
  # Simulate interruption after arming without discarding per-plist ownership.
  perl -pi -e 's/"phase": "steady"/"phase": "arming"/' "$STATE/state.json"
  run "$RUNNER" install --apply
  [ "$status" -eq 0 ]
  grep -Fq '"intent": "disabled"' "$STATE/state.json"
  [ ! -f "$MOCK_LAUNCH_STATE/agent" ]
  run "$RUNNER" doctor
  [ "$status" -eq 0 ]
}

@test "first-enable native option writes reconcile after SIGKILL at each atomic replacement" {
  local kill_at count
  for kill_at in 1 2 3 4; do
    use_two_peer_fixture
    write_fake_password
    count="$SANDBOX/mv-count"
    printf '0\n' >"$count"
    export MOCK_KILL_MV_WHEN="$kill_at" MOCK_MV_COUNT_FILE="$count"
    cat >"$MOCK/mv" <<'EOF'
#!/bin/sh
/bin/mv "$@" || exit 1
case "$*" in
  *RustDesk2.toml)
    count="$(/bin/cat "$MOCK_MV_COUNT_FILE")"
    count="$((count + 1))"
    printf '%s\n' "$count" >"$MOCK_MV_COUNT_FILE"
    [ "$count" != "$MOCK_KILL_MV_WHEN" ] || kill -KILL "$PPID" ;;
esac
EOF
    chmod +x "$MOCK/mv"
    run "$RUNNER" enable --apply --peer green
    [ "$status" -ne 0 ]
    unset MOCK_KILL_MV_WHEN MOCK_MV_COUNT_FILE
    rm "$MOCK/mv"
    run "$RUNNER" doctor
    [ "$status" -eq 1 ]
    run "$RUNNER" disable --apply
    [ "$status" -eq 0 ] || { printf 'kill_at=%s: %s\n' "$kill_at" "$output" >&2; return 1; }
    run "$RUNNER" doctor
    [ "$status" -eq 0 ]
    teardown
    setup
  done
}

@test "interrupted daemon and agent copies reconcile each individual ownership claim" {
  local label
  for label in com.carriez.RustDesk_service com.carriez.RustDesk_server; do
    use_two_peer_fixture
    write_fake_password
    export MOCK_KILL_ON_COPY_LABEL="$label"
    run "$RUNNER" enable --apply --peer green
    [ "$status" -ne 0 ]
    unset MOCK_KILL_ON_COPY_LABEL
    run "$RUNNER" disable --apply
    [ "$status" -eq 0 ] || return 1
    run "$RUNNER" doctor
    [ "$status" -eq 0 ]
    teardown
    setup
  done
}

@test "failed launchctl startup at each job step reconciles to safe off" {
  local step
  for step in 'bootstrap system' 'bootstrap gui/'; do
    use_two_peer_fixture
    write_fake_password
    export MOCK_FAIL_LAUNCH_MATCH="$step"
    run "$RUNNER" enable --apply --peer green
    [ "$status" -ne 0 ] || { printf 'unexpected startup success at %s\n' "$step" >&2; return 1; }
    unset MOCK_FAIL_LAUNCH_MATCH
    run "$RUNNER" disable --apply
    [ "$status" -eq 0 ] || return 1
    run "$RUNNER" doctor
    [ "$status" -eq 0 ]
    teardown
    setup
  done
}

@test "SIGKILL at each launchctl startup step is reconciled by re-entry" {
  local step
  for step in 'bootstrap system' 'bootstrap gui/'; do
    use_two_peer_fixture
    write_fake_password
    export MOCK_KILL_LAUNCH_MATCH="$step"
    run "$RUNNER" enable --apply --peer green
    [ "$status" -ne 0 ] || return 1
    unset MOCK_KILL_LAUNCH_MATCH
    run "$RUNNER" doctor
    [ "$status" -eq 1 ]
    run "$RUNNER" disable --apply
    [ "$status" -eq 0 ] || { printf 'step=%s: %s\n' "$step" "$output" >&2; return 1; }
    teardown
    setup
  done
}

@test "peer tailnet context change cannot rebind a matching node ID" {
  enabled_fixture
  export MOCK_TAILSCALE_JSON="$SANDBOX/foreign-tailnet.json"
  printf '%s\n' '{"BackendState":"Running","Self":{"Online":true},"CurrentTailnet":{"Name":"different-tailnet.ts.net"},"Peer":{"green":{"ID":"node-green","HostName":"iphone-green","OS":"iOS","Online":true,"TailscaleIPs":["100.64.50.3","fd7a:115c:a1e0::3"]}}}' >"$MOCK_TAILSCALE_JSON"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"peer-stale"* ]]
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  [[ "$output" == *"rebind"* ]]
}

@test "missing native stop readback prevents any direct-IP or plist change" {
  use_two_peer_fixture
  write_fake_password
  export MOCK_REAL_PYTHON="$(command -v python3)"
  cat >"$MOCK/python3" <<'EOF'
#!/bin/sh
case " $* " in *' --set stop-service Y '*) exit 1 ;; esac
exec "$MOCK_REAL_PYTHON" "$@"
EOF
  chmod +x "$MOCK/python3"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  [ ! -f "$MOCK_ROOT/Library/LaunchDaemons/com.carriez.RustDesk_service.plist" ]
  ! grep -Fq "direct-server = 'Y'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
}

@test "noninteractive sudo denial cannot make disabled doctor report green" {
  enabled_fixture
  run "$RUNNER" disable --apply
  [ "$status" -eq 0 ]
  export MOCK_SUDO_FAIL_MATCH='/bin/sh -c'
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"listener unknown"* ]]
}

@test "active enable preflight revokes stale access if selected peer goes offline" {
  enabled_fixture
  export MOCK_TAILSCALE_JSON="$SANDBOX/peer-offline.json"
  printf '%s\n' '{"BackendState":"Running","Self":{"Online":true},"CurrentTailnet":{"Name":"test-tailnet.ts.net"},"Peer":{"green":{"ID":"node-green","HostName":"iphone-green","OS":"iOS","Online":false,"TailscaleIPs":["100.64.50.3","fd7a:115c:a1e0::3"]}}}' >"$MOCK_TAILSCALE_JSON"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  grep -Fq '"intent": "disabled"' "$STATE/state.json"
  [ ! -f "$MOCK_LAUNCH_STATE/agent" ]
  grep -Fq "direct-server = 'N'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
}

@test "active enable stops old listener before failing backend service preflight" {
  enabled_fixture
  cat >"$MOCK/tailscale" <<'EOF'
#!/bin/sh
printf 'tailscale %s\n' "$*" >>"$MUTATE_LOG"
case "$1" in
  status) printf 'failed to connect to local tailscaled\n' >&2; exit 1 ;;
  version) printf '1.102.3\n'; exit 0 ;;
esac
exit 1
EOF
  chmod +x "$MOCK/tailscale"
  export MOCK_SUDO_FAIL_MATCH='brew services start tailscale'
  : >"$MUTATE_LOG"
  run "$RUNNER" enable --apply --peer green
  [ "$status" -ne 0 ]
  grep -Fq '"intent": "disabled"' "$STATE/state.json"
  grep -Fq "stop-service = 'Y'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  grep -Fq "direct-server = 'N'" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  [ ! -f "$MOCK_LAUNCH_STATE/agent" ]
  local bootout_line brew_line
  bootout_line="$(grep -m1 -n 'launchctl bootout gui/' "$MUTATE_LOG" | cut -d: -f1)"
  brew_line="$(grep -n 'sudo brew services start tailscale' "$MUTATE_LOG" | cut -d: -f1)"
  [ "$bootout_line" -lt "$brew_line" ]
}

@test "enabled doctor rejects same node ID renamed to a different host" {
  enabled_fixture
  export MOCK_TAILSCALE_JSON="$SANDBOX/renamed.json"
  printf '%s\n' '{"BackendState":"Running","Self":{"Online":true},"CurrentTailnet":{"Name":"test-tailnet.ts.net"},"Peer":{"renamed":{"ID":"node-green","HostName":"another-host","OS":"iOS","Online":true,"TailscaleIPs":["100.64.50.3","fd7a:115c:a1e0::3"]}}}' >"$MOCK_TAILSCALE_JSON"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"peer-stale"* ]]
  run "$RUNNER" enable --apply --peer another-host
  [ "$status" -ne 0 ]
  grep -Fq '"intent": "disabled"' "$STATE/state.json"
}

@test "rollback leaves modified backup untouched while plists are retained" {
  use_two_peer_fixture
  local options="$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  printf '%s\n' '[options]' "keep-me = 'yes'" >"$options"
  write_fake_password
  run "$RUNNER" enable --apply --peer green
  [ "$status" -eq 0 ]
  printf '%s\n' 'operator changed backup' >>"$STATE/backups/RustDesk2.original"
  run "$RUNNER" rollback --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"plist retained for attended review"* ]]
  grep -Fq 'operator changed backup' "$STATE/backups/RustDesk2.original"
  grep -Fq "direct-server = 'N'" "$options"
  ! grep -Fq '"intent": "rolled-back"' "$STATE/state.json"
}

@test "disabled doctor rejects ambiguous duplicate native stop values" {
  enabled_fixture
  run "$RUNNER" disable --apply
  [ "$status" -eq 0 ]
  printf '%s\n' "stop-service = 'N'" >>"$DEST_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  run "$RUNNER" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"ambiguous native options"* ]]
}
