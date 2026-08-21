#!/usr/bin/env bash
# Offline behavior matrix for the Kopia nightly runner.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/rig/home/dot_local/bin/executable_kopia-nightly"
STUB_BIN="$ROOT/checks/fixtures/kopia-nightly/bin"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/kopia-nightly-fixtures.XXXXXX")"
fail=0

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail_msg() {
  printf 'kopia-nightly-fixtures: %s\n' "$*" >&2
  fail=1
}

line_count() {
  local needle="$1"
  local file="$2"
  awk -v needle="$needle" 'index($0, needle) { count++ } END { print count + 0 }' "$file"
}

assert_count() {
  local expected="$1"
  local needle="$2"
  local file="$3"
  local label="$4"
  local actual
  actual="$(line_count "$needle" "$file")"
  if [[ "$actual" -ne "$expected" ]]; then
    fail_msg "$label: expected $expected occurrence(s) of [$needle], got $actual"
  fi
}

prepare_case() {
  local name="$1"
  local case_dir="$TEST_ROOT/$name"
  mkdir -p "$case_dir/home/Library/Logs/kopia/tmp" "$case_dir/state"
  : >"$case_dir/home/.bashrc"
  : >"$case_dir/state/calls"
  printf '%s\n' "$case_dir"
}

invoke_case() {
  local name="$1"
  local scenario="$2"
  local expected_rc="$3"
  local expected_notifications="$4"
  local mode="$5"
  local expected_notice="${6:-}"
  local case_dir calls rc
  case_dir="$(prepare_case "$name")"
  calls="$case_dir/state/calls"

  set +e
  if [[ "$mode" == "public" ]]; then
    env \
      HOME="$case_dir/home" \
      PATH="$STUB_BIN:/usr/bin:/bin" \
      XPC_SERVICE_NAME="com.wyattowalsh.kopia-nightly" \
      KOPIA_NIGHTLY_TEST_BIN="$STUB_BIN" \
      KOPIA_NIGHTLY_TEST_STATE="$case_dir/state" \
      KOPIA_NIGHTLY_TEST_SCENARIO="$scenario" \
      "$RUNNER" >"$case_dir/stdout" 2>"$case_dir/stderr"
    rc=$?
  else
    env \
      HOME="$case_dir/home" \
      PATH="$STUB_BIN:/usr/bin:/bin" \
      XPC_SERVICE_NAME="com.wyattowalsh.kopia-nightly" \
      KOPIA_NIGHTLY_TEST_BIN="$STUB_BIN" \
      KOPIA_NIGHTLY_TEST_STATE="$case_dir/state" \
      KOPIA_NIGHTLY_TEST_SCENARIO="$scenario" \
      "$RUNNER" __bounded-run >"$case_dir/stdout" 2>"$case_dir/stderr"
    rc=$?
  fi
  set -e

  if [[ "$rc" -ne "$expected_rc" ]]; then
    fail_msg "$name: expected exit $expected_rc, got $rc"
  fi
  assert_count "$expected_notifications" 'osascript|' "$calls" "$name notification count"
  if [[ -n "$expected_notice" ]]; then
    assert_count 1 "osascript|-e display notification \"$expected_notice\"" "$calls" "$name notification text"
  fi
  assert_count 1 'flock|-n 9' "$calls" "$name single-run lock"
  assert_count 0 '--progress' "$calls" "$name launchd progress suppression"
}

invoke_preview_case() {
  local name="$1"
  shift
  local case_dir calls rc
  case_dir="$(prepare_case "$name")"
  calls="$case_dir/state/calls"

  set +e
  env \
    HOME="$case_dir/home" \
    PATH="$STUB_BIN:/usr/bin:/bin" \
    KOPIA_NIGHTLY_TEST_BIN="$STUB_BIN" \
    KOPIA_NIGHTLY_TEST_STATE="$case_dir/state" \
    KOPIA_NIGHTLY_TEST_SCENARIO="success" \
    "$RUNNER" "$@" >"$case_dir/stdout" 2>"$case_dir/stderr"
  rc=$?
  set -e

  if [[ "$rc" -ne 0 ]]; then
    fail_msg "$name: expected preview exit 0, got $rc"
  fi
  assert_count 0 'gtimeout|' "$calls" "$name wrapper bypass"
  assert_count 0 'kopia|' "$calls" "$name repository isolation"
  assert_count 0 'launchctl|' "$calls" "$name launchctl isolation"
  assert_count 0 'flock|' "$calls" "$name lock isolation"
  assert_count 0 'osascript|' "$calls" "$name notification isolation"
}

run_signal_case() {
  local name="$1"
  local signal="$2"
  local expected_rc="$3"
  local case_dir calls pid rc ready=0
  case_dir="$(prepare_case "$name")"
  calls="$case_dir/state/calls"

  # Job control keeps SIGINT from being inherited as ignored by the disposable
  # background runner. The runner remains the only process we signal.
  set -m
  env \
    HOME="$case_dir/home" \
    PATH="$STUB_BIN:/usr/bin:/bin" \
    XPC_SERVICE_NAME="com.wyattowalsh.kopia-nightly" \
    KOPIA_NIGHTLY_TEST_BIN="$STUB_BIN" \
    KOPIA_NIGHTLY_TEST_STATE="$case_dir/state" \
    KOPIA_NIGHTLY_TEST_SCENARIO="success" \
    KOPIA_NIGHTLY_TEST_SIGNAL_WAIT=1 \
    "$RUNNER" __bounded-run >"$case_dir/stdout" 2>"$case_dir/stderr" &
  pid=$!
  set +m

  for _ in $(seq 1 100); do
    if [[ -f "$case_dir/state/signal-ready" ]]; then
      ready=1
      break
    fi
    /bin/sleep 0.05
  done
  if [[ "$ready" -ne 1 ]]; then
    kill -KILL "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
    fail_msg "$name: runner did not reach the disposable signal barrier"
    return
  fi

  kill "-$signal" "$pid"
  stopped=0
  for _ in $(seq 1 100); do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      stopped=1
      break
    fi
    state="$(/bin/ps -p "$pid" -o state= 2>/dev/null || true)"
    if [[ "$state" == Z* ]]; then
      stopped=1
      break
    fi
    /bin/sleep 0.05
  done
  if [[ "$stopped" -ne 1 ]]; then
    kill -KILL "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
    fail_msg "$name: disposable runner did not stop after $signal"
    return
  fi
  set +e
  wait "$pid"
  rc=$?
  set -e

  if [[ "$rc" -ne "$expected_rc" ]]; then
    fail_msg "$name: expected exit $expected_rc after $signal, got $rc"
  fi
  assert_count 1 'osascript|' "$calls" "$name notification count"
  assert_count 1 'osascript|-e display notification "Kopia nightly failed; check the local log"' "$calls" "$name failure notification"
}

invoke_case success success 0 0 public
success_calls="$TEST_ROOT/success/state/calls"
assert_count 1 'gtimeout|--verbose --signal=TERM --kill-after=60s 43140s' "$success_calls" 'success whole-run wrapper'
assert_count 1 'gtimeout|--signal=TERM --kill-after=5s 30s kopia repository status' "$success_calls" 'success status timeout'
assert_count 4 'launchctl|disable ' "$success_calls" 'success start/final label disable'

invoke_case readiness-exhaustion readiness_exhaustion 1 1 private 'Kopia nightly failed; check the local log'
readiness_calls="$TEST_ROOT/readiness-exhaustion/state/calls"
assert_count 8 'gtimeout|--signal=TERM --kill-after=5s 30s kopia repository status' "$readiness_calls" 'readiness retry count'
for delay in 5 10 20 30; do
  expected=1
  [[ "$delay" -eq 30 ]] && expected=4
  assert_count "$expected" "sleep|$delay" "$readiness_calls" "readiness delay $delay"
done

invoke_case status-timeout status_timeout 1 1 private 'Kopia nightly failed; check the local log'
timeout_calls="$TEST_ROOT/status-timeout/state/calls"
assert_count 8 'gtimeout|--signal=TERM --kill-after=5s 30s kopia repository status' "$timeout_calls" 'status timeout retry count'
assert_count 0 'kopia|repository status' "$timeout_calls" 'status timeout never reaches hung command'

invoke_case lock-contention lock_contention 1 1 private 'Kopia nightly failed; check the local log'
contention_calls="$TEST_ROOT/lock-contention/state/calls"
assert_count 0 'gtimeout|--signal=TERM --kill-after=5s 30s kopia repository status' "$contention_calls" 'lock contention stops before repository readiness'
assert_count 0 'kopia|snapshot create' "$contention_calls" 'lock contention stops before snapshots'
assert_count 0 'caffeinate|' "$contention_calls" 'lock contention stops before sleep inhibition'
assert_count 2 'launchctl|disable ' "$contention_calls" 'lock contention final cleanup'

invoke_case snapshot-failure snapshot_failure 1 1 private 'Kopia nightly failed; check the local log'
invoke_case maintenance-warning maintenance_warning 0 1 private 'Kopia nightly maintenance needs attention'
invoke_case cleanup-failure cleanup_failure 1 1 private 'Kopia nightly failed; check the local log'
invoke_case notification-failure notification_failure 1 1 private 'Kopia nightly failed; check the local log'
invoke_case combined-failure combined_failure 1 1 private 'Kopia nightly failed; check the local log'
run_signal_case term TERM 143
run_signal_case int INT 130
invoke_preview_case run-dry-run --dry-run
invoke_preview_case install-dry-run install --dry-run

if [[ "$fail" -ne 0 ]]; then
  printf 'kopia-nightly-fixtures: FAIL\n' >&2
  exit 1
fi

printf 'kopia-nightly-fixtures: ok\n'
