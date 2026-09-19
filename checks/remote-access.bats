#!/usr/bin/env bats
# Offline remote-access checks (no live launchctl, brew, TCC, or power writes).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/remote-access-bats.XXXXXX")"
  DEST_HOME="$SANDBOX/dest home"
  MOCK="$SANDBOX/mock-bin"
  STATE="$SANDBOX/state"
  mkdir -p "$DEST_HOME/.local/bin" "$DEST_HOME/Library/Preferences/com.carriez.RustDesk" "$MOCK" "$STATE"
  export HOME="$DEST_HOME"
  export REMOTE_ACCESS_REPO="$REPO_ROOT"
  export REMOTE_ACCESS_STATE_DIR="$STATE"
  export REMOTE_ACCESS_UNAME="Darwin"
  export REMOTE_ACCESS_SKIP_OPEN=1
  export REMOTE_ACCESS_SUDO="$MOCK/sudo"
  export MUTATE_LOG="$SANDBOX/mutate.log"
  : >"$MUTATE_LOG"

  cat >"$MOCK/sudo" <<'EOF'
#!/bin/sh
echo "sudo $*" >>"${MUTATE_LOG}"
exit 0
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
      cat <<'JSON'
{"BackendState":"Running","Self":{"Online":true,"HostName":"w4w-mbp","OS":"macOS","TailscaleIPs":["100.64.0.1","fd7a:115c:a1e0::1"]},"Peer":{"n":{"HostName":"iphone-ww","OS":"iOS","Online":true,"DNSName":"iphone-ww.tailnet.ts.net","TailscaleIPs":["100.64.0.2","fd7a:115c:a1e0::2"]}}}
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
exit 0
EOF
  cat >"$MOCK/lsof" <<'EOF'
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
  RUNNER="$REPO_ROOT/rig/home/dot_local/bin/executable_remote-access"
}

teardown() {
  rm -rf "$SANDBOX"
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
