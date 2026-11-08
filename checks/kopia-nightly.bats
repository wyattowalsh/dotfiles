#!/usr/bin/env bats
# Isolated runner functions only: no Kopia, launchctl, credentials or services.
# shellcheck disable=SC2016 # Child bash intentionally expands its own variables.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TASK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kopia-nightly-bats.XXXXXX")"
  export TASK_DIR
  local runner="$REPO_ROOT/rig/home/dot_local/bin/executable_kopia-nightly"
  [ "$(tail -n 1 "$runner")" = 'main "$@"' ]
  sed '$d' "$runner" >"$TASK_DIR/functions.sh"
  printf 'fixture\n' >"$TASK_DIR/source with spaces"
  printf '0\n' >"$TASK_DIR/clock"
  cat >"$TASK_DIR/harness.sh" <<'BASH'
source "$TASK_DIR/functions.sh"
LOG_DIR="$TASK_DIR"
TMP_DIR="$TASK_DIR"
require_cmd() { :; }
runtime_paths() { :; }
resolve_timeout_bin() { printf 'mock-timeout\n'; }
snapshot_timeout_sec() { printf '100\n'; }
flock() { :; }
ensure_kopiaui_quit() { :; }
ensure_login_disabled() { :; }
emit_outcome_notification() { printf '%s\n' "$1" >>"$TASK_DIR/notifications"; }
sleep() { printf '%s\n' "$1" >>"$TASK_DIR/sleeps"; }
# Lifecycle cleanup is outside these argv/maintenance cases.
trap() { :; }
command() {
  if [[ "$*" == '-v caffeinate' ]]; then return 1; fi
  builtin command "$@"
}
source_list() { printf '%s\n' "$TASK_DIR/source with spaces"; }
date() {
  local tick
  tick="$(<"$TASK_DIR/clock")"
  printf '%s\n' "$((tick + 1))" >"$TASK_DIR/clock"
  case "$tick" in
    0 | 1) printf '100\n' ;;
    2 | 3) printf '105\n' ;;
    *) printf '%s\n' "${TASK_END:-160}" ;;
  esac
}
run_timeout() {
  printf '<%s>' "$@" >>"$TASK_DIR/calls"
  printf '\n' >>"$TASK_DIR/calls"
  case "$3" in
    snapshot)
      local attempt=0
      [[ ! -f "$TASK_DIR/snapshot-attempt" ]] || attempt="$(<"$TASK_DIR/snapshot-attempt")"
      attempt=$((attempt + 1))
      printf '%s\n' "$attempt" >"$TASK_DIR/snapshot-attempt"
      if [[ "$attempt" -le "${TASK_RETRY_FAILURES:-0}" ]]; then
        printf '%s\n' "${TASK_RETRY_MESSAGE:-ERROR failed to open repository: cannot open storage: unable to start rclone: timed out waiting for rclone to start}"
        return 7
      fi
      return "${TASK_SNAPSHOT_RC:-0}"
      ;;
    maintenance) return "${TASK_MAINTENANCE_RC:-0}" ;;
    *) return 99 ;;
  esac
}
run_timeout_with_grace() {
  printf '<%s>' "$@" >>"$TASK_DIR/readiness-calls"
  printf '\n' >>"$TASK_DIR/readiness-calls"
  local attempt=0
  [[ ! -f "$TASK_DIR/ready-attempt" ]] || attempt="$(<"$TASK_DIR/ready-attempt")"
  attempt=$((attempt + 1))
  printf '%s\n' "$attempt" >"$TASK_DIR/ready-attempt"
  [[ "$attempt" -gt "${TASK_READY_FAILURES:-0}" ]]
}
BASH
}

teardown() {
  /bin/rm -rf -- "$TASK_DIR"
}

role_fixture() {
  bash -c '
    source "$TASK_DIR/functions.sh"
    uname() { printf "%s\n" "${TASK_OS:-Darwin}"; }
    hostname() { printf "%s\n" "${TASK_HOST:-MacBookAir}"; }
    id() {
      if [[ "${TASK_ID_FAILURE:-0}" == 1 ]]; then
        printf "fixture identity failure\n" >&2
        return 7
      fi
      case "$1" in
        -un) printf "%s\n" "${TASK_USER:-wyattwalsh}" ;;
        -u) printf "%s\n" "${TASK_UID:-501}" ;;
      esac
    }
    cmd_run() { printf "run:%s\n" "$1" >>"$TASK_DIR/role-dispatch"; }
    cmd_install() { printf "install:%s\n" "$1" >>"$TASK_DIR/role-dispatch"; }
    cmd_bounded_run() { printf "bounded:%s\n" "$1" >>"$TASK_DIR/role-dispatch"; }
    cmd_doctor() { printf "doctor:%s\n" "$1"; }
    main "$@"
  ' role-fixture "$@"
}

@test "exact MBA denies Nightly install and run before dispatch but permits doctor" {
  local mode
  run role_fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *'the MBA uses its native KopiaUI scheduler'* ]]
  for mode in install --dry-run __bounded-run; do
    run role_fixture "$mode"
    [ "$status" -eq 1 ]
    [[ "$output" == *'the MBA uses its native KopiaUI scheduler'* ]]
  done
  [ ! -e "$TASK_DIR/role-dispatch" ]
  run role_fixture doctor --policies
  [ "$status" -eq 0 ]
  [ "$output" = 'doctor:1' ]
  [ ! -e "$TASK_DIR/role-dispatch" ]
}

@test "bootstrap role predicate is silent and MBP dispatch is unchanged" {
  run role_fixture __mba-role
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  export TASK_HOST=w4w-mbp TASK_USER=ww TASK_UID=502
  run role_fixture __mba-role
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  run role_fixture install --dry-run
  [ "$status" -eq 0 ]
  run role_fixture __bounded-run
  [ "$status" -eq 0 ]
  [ "$(<"$TASK_DIR/role-dispatch")" = $'install:1\nbounded:0' ]
}

@test "unreadable MBA identity fails closed and the role predicate stays silent" {
  export TASK_ID_FAILURE=1
  run role_fixture __mba-role
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  run role_fixture __bounded-run
  [ "$status" -eq 1 ]
  [[ "$output" == *'cannot establish the native backup host role'* ]]
  [ ! -e "$TASK_DIR/role-dispatch" ]
}

@test "non-TTY snapshots preserve source/flags and maintenance gets remaining cap" {
  run bash -c 'source "$TASK_DIR/harness.sh"; cmd_bounded_run 0'
  [ "$status" -eq 0 ]
  local expected
  expected="<95><kopia><snapshot><create><--fail-fast><$TASK_DIR/source with spaces>"
  expected+=$'\n<40><kopia><maintenance><run><--full>'
  [ "$(<"$TASK_DIR/calls")" = "$expected" ]
  [[ "$output" == *'summary ok=1 skip=0 fail=0'* ]]
  [[ "$output" == *'maintenance run --full rc=0'* ]]
}

@test "failed snapshot loop does not enter maintenance" {
  run env TASK_SNAPSHOT_RC=7 bash -c 'source "$TASK_DIR/harness.sh"; cmd_bounded_run 0'
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$TASK_DIR/calls" | tr -d ' ')" -eq 1 ]
  [[ "$output" == *'summary ok=0 skip=0 fail=1'* ]]
  [[ "$output" != *'maintenance run --full'* ]]
}

@test "timeout and killed snapshot loops do not enter maintenance" {
  local rc
  for rc in 124 137; do
    printf '0\n' >"$TASK_DIR/clock"
    : >"$TASK_DIR/calls"
    run env TASK_SNAPSHOT_RC="$rc" bash -c 'source "$TASK_DIR/harness.sh"; cmd_bounded_run 0'
    [ "$status" -eq 1 ]
    [ "$(wc -l <"$TASK_DIR/calls" | tr -d ' ')" -eq 1 ]
    [[ "$output" == *"cap reached (100s) rc=$rc"* ]]
  done
}

@test "maintenance failure warns and preserves successful snapshots" {
  run env TASK_MAINTENANCE_RC=9 bash -c 'source "$TASK_DIR/harness.sh"; cmd_bounded_run 0'
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$TASK_DIR/calls" | tr -d ' ')" -eq 2 ]
  [[ "$output" == *'maintenance run --full rc=9'* ]]
  [[ "$output" == *'warning: full maintenance failed; snapshot result unchanged'* ]]
}

@test "exhausted overall cap warns and skips maintenance" {
  run env TASK_END=200 bash -c 'source "$TASK_DIR/harness.sh"; cmd_bounded_run 0'
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$TASK_DIR/calls" | tr -d ' ')" -eq 1 ]
  [[ "$output" == *'warning: full maintenance skipped (wall-clock cap exhausted)'* ]]
}

@test "EXIT cleanup retains caffeine PID after bounded function returns" {
  run bash -c '
    source "$TASK_DIR/harness.sh"
    unset -f trap
    command() {
      if [[ "$*" == "-v caffeinate" ]]; then return 0; fi
      builtin command "$@"
    }
    caffeinate() { :; }
    kill() { printf "kill:%s\n" "$1" >>"$TASK_DIR/cleanup"; }
    ensure_login_disabled() { printf "login-disabled\n" >>"$TASK_DIR/cleanup"; }
    cmd_bounded_run 0
    printf "%s\n" "$caffeine_pid" >"$TASK_DIR/caffeine-pid"
    printf "returned\n" >>"$TASK_DIR/cleanup"
  '
  [ "$status" -eq 0 ]
  local caffeine_pid expected
  caffeine_pid="$(<"$TASK_DIR/caffeine-pid")"
  [[ "$caffeine_pid" =~ ^[1-9][0-9]*$ ]]
  expected=$'login-disabled\nreturned\nlogin-disabled\n'"kill:$caffeine_pid"
  [ "$(<"$TASK_DIR/cleanup")" = "$expected" ]
}

@test "timeout wrapper retains kill grace and exact argv without native execution" {
  run bash -c '
    source "$TASK_DIR/functions.sh"
    command() {
      if [[ "$1" == -v && "$2" == timeout ]]; then return 0; fi
      printf "<%s>" "$@"
    }
    run_timeout 95 kopia snapshot create --fail-fast "$TASK_DIR/source with spaces"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "<timeout><--signal=TERM><--kill-after=60><95><kopia><snapshot><create><--fail-fast><$TASK_DIR/source with spaces>" ]
}

@test "normal entry uses one whole-run timeout including setup and readiness" {
  run bash -c '
    source "$TASK_DIR/harness.sh"
    exec() { printf "<%s>" "$@"; }
    cmd_run 0
  '
  [ "$status" -eq 0 ]
  [ "$output" = '<mock-timeout><--verbose><--signal=TERM><--kill-after=60><100><bash><__bounded-run>' ]
  [ ! -e "$TASK_DIR/calls" ]
}

@test "nested normal-run timers stay in the outer process group" {
  run bash -c '
    source "$TASK_DIR/functions.sh"
    RUN_BOUNDED=1
    command() {
      if [[ "$1" == -v && "$2" == timeout ]]; then return 0; fi
      printf "<%s>" "$@"
    }
    run_timeout_with_grace 5 125 kopia repository status
  '
  [ "$status" -eq 0 ]
  [ "$output" = '<timeout><--signal=TERM><--kill-after=5><--foreground><125><kopia><repository><status>' ]
}

@test "repository readiness retries finitely before snapshots" {
  run env TASK_READY_FAILURES=2 bash -c '
    source "$TASK_DIR/harness.sh"
    date() { printf "100\n"; }
    cmd_bounded_run 0
  '
  [ "$status" -eq 0 ]
  [ "$(<"$TASK_DIR/ready-attempt")" -eq 3 ]
  [ "$(<"$TASK_DIR/sleeps")" = $'5\n10' ]
  [[ "$output" == *'repository status attempt 3/8'* ]]
  [[ "$(<"$TASK_DIR/readiness-calls")" == *'<5><100><kopia><repository><status>'* ]]
}

@test "repository readiness exhaustion never starts snapshots or maintenance" {
  run env TASK_READY_FAILURES=8 bash -c '
    source "$TASK_DIR/harness.sh"
    date() { printf "100\n"; }
    cmd_bounded_run 0
  '
  [ "$status" -eq 1 ]
  [ "$(<"$TASK_DIR/ready-attempt")" -eq 8 ]
  [ "$(<"$TASK_DIR/sleeps")" = $'5\n10\n20\n30\n30\n30\n30' ]
  [ ! -e "$TASK_DIR/calls" ]
  [[ "$output" == *'repository unreachable after 8 attempts'* ]]
}

@test "readiness stops when the shared budget expires before eight attempts" {
  run env TASK_READY_FAILURES=8 TASK_END=200 bash -c '
    source "$TASK_DIR/harness.sh"
    cmd_bounded_run 0
  '
  [ "$status" -eq 1 ]
  [ "$(<"$TASK_DIR/ready-attempt")" -eq 2 ]
  [ "$(<"$TASK_DIR/sleeps")" = 5 ]
  [ ! -e "$TASK_DIR/calls" ]
  [[ "$output" == *'repository readiness wall-clock cap reached (100s)'* ]]
}

@test "rclone timeout retries stop after three attempts and retain argv" {
  run env TASK_RETRY_FAILURES=3 bash -c '
    source "$TASK_DIR/harness.sh"
    date() { printf "100\n"; }
    cmd_bounded_run 0
  '
  [ "$status" -eq 1 ]
  [ "$(<"$TASK_DIR/snapshot-attempt")" -eq 3 ]
  [ "$(wc -l <"$TASK_DIR/calls" | tr -d ' ')" -eq 3 ]
  [[ "$output" == *'snapshot retry 3/3:'* ]]
  [[ "$output" == *'summary ok=0 skip=0 fail=1'* ]]
  [[ "$output" != *'maintenance run --full'* ]]
}

@test "rclone timeout can recover while unrelated errors are not retried" {
  run env TASK_RETRY_FAILURES=2 bash -c '
    source "$TASK_DIR/harness.sh"
    cmd_bounded_run 0
  '
  [ "$status" -eq 0 ]
  [ "$(<"$TASK_DIR/snapshot-attempt")" -eq 3 ]
  [[ "$(<"$TASK_DIR/calls")" == '<95><kopia><snapshot>'* ]]
  [[ "$(<"$TASK_DIR/calls")" == *'<40><kopia><snapshot>'* ]]
  [[ "$output" == *'summary ok=1 skip=0 fail=0'* ]]
  rm -f "$TASK_DIR/snapshot-attempt" "$TASK_DIR/calls"
  run env TASK_RETRY_FAILURES=2 TASK_RETRY_MESSAGE='unrelated timeout' bash -c '
    source "$TASK_DIR/harness.sh"
    date() { printf "100\n"; }
    cmd_bounded_run 0
  '
  [ "$status" -eq 1 ]
  [ "$(<"$TASK_DIR/snapshot-attempt")" -eq 1 ]
}

@test "unreadable filename containing rclone and timeout fails once and later root is attempted" {
  printf 'later fixture\n' >"$TASK_DIR/later root"
  run env TASK_RETRY_FAILURES=1 TASK_RETRY_MESSAGE='ERROR upload error: read /private/Documents/rclone timeout.txt: resource deadlock avoided' bash -c '
    source "$TASK_DIR/harness.sh"
    date() { printf "100\n"; }
    source_list() { printf "%s\n" "$TASK_DIR/source with spaces" "$TASK_DIR/later root"; }
    cmd_bounded_run 0
  '
  [ "$status" -eq 1 ]
  [ "$(<"$TASK_DIR/snapshot-attempt")" -eq 2 ]
  local expected="<100><kopia><snapshot><create><--fail-fast><$TASK_DIR/source with spaces>"
  expected+=$'\n'"<100><kopia><snapshot><create><--fail-fast><$TASK_DIR/later root>"
  [ "$(<"$TASK_DIR/calls")" = "$expected" ]
  [[ "$output" == *'summary ok=1 skip=0 fail=1'* ]]
  [[ "$output" != *'snapshot retry'* ]]
  [[ "$output" != *'maintenance run --full'* ]]
}

@test "startup-timeout words and diagnostic text inside file errors are not transport retries" {
  local message
  for message in \
    'rclone start timeout' \
    'ERROR upload error: read /private/ERROR failed to open repository: cannot open storage: unable to start rclone: timed out waiting for rclone to start: resource deadlock avoided' \
    'ERROR failed to open repository: cannot open storage: unable to start rclone: rclone server failed to start: timeout'; do
    rm -f "$TASK_DIR/snapshot-attempt" "$TASK_DIR/calls"
    run env TASK_RETRY_FAILURES=3 TASK_RETRY_MESSAGE="$message" bash -c '
      source "$TASK_DIR/harness.sh"
      date() { printf "100\n"; }
      cmd_bounded_run 0
    '
    [ "$status" -eq 1 ]
    [ "$(<"$TASK_DIR/snapshot-attempt")" -eq 1 ]
    [[ "$output" != *'snapshot retry'* ]]
  done
}

@test "terminal progress retains fail-fast and launchd suppresses forced progress" {
  command -v script >/dev/null 2>&1 || skip 'script unavailable for isolated PTY fixture'
  cat >"$TASK_DIR/pty.sh" <<'BASH'
[[ -t 1 ]] || exit 1
# macOS can set XPC_SERVICE_NAME when launching script or its child.
export XPC_SERVICE_NAME="$TASK_LAUNCHD_NAME"
source "$TASK_DIR/harness.sh"
date() { printf '100\n'; }
cmd_bounded_run 0
BASH
  local launchd_name
  for launchd_name in '' 'fixture.launchd'; do
    rm -f "$TASK_DIR/calls"
    if [[ "$(uname -s)" == Darwin ]]; then
      run env TASK_LAUNCHD_NAME="$launchd_name" script -q /dev/null bash "$TASK_DIR/pty.sh"
    else
      run env TASK_LAUNCHD_NAME="$launchd_name" script -q -c 'bash "$TASK_DIR/pty.sh"' /dev/null
    fi
    [ "$status" -eq 0 ]
    if [[ -z "$launchd_name" ]]; then
      [[ "$(<"$TASK_DIR/calls")" == '<100><kopia><snapshot><create><--progress><--fail-fast>'* ]]
    else
      [[ "$(<"$TASK_DIR/calls")" == '<100><kopia><snapshot><create><--fail-fast>'* ]]
    fi
  done
}

@test "TERM and INT exit once after cleanup and failure notification" {
  local signal expected_status
  for signal in TERM INT; do
    expected_status=143
    [[ "$signal" != INT ]] || expected_status=130
    rm -f "$TASK_DIR/cleanup" "$TASK_DIR/notifications"
    run env TASK_SIGNAL="$signal" bash -c '
      source "$TASK_DIR/harness.sh"
      unset -f trap
      ensure_login_disabled() { printf "disabled\n" >>"$TASK_DIR/cleanup"; }
      wait_repo_ready() {
        RUN_TEMP_FILE="$TMP_DIR/kopia-nightly.signal"
        printf "temporary\n" >"$RUN_TEMP_FILE"
        builtin kill -s "$TASK_SIGNAL" "$$"
        printf "continued\n" >>"$TASK_DIR/cleanup"
      }
      cmd_bounded_run 0
    '
    [ "$status" -eq "$expected_status" ]
    [ "$(<"$TASK_DIR/cleanup")" = $'disabled\ndisabled' ]
    [ "$(<"$TASK_DIR/notifications")" = failure ]
    [ ! -e "$TASK_DIR/kopia-nightly.signal" ]
  done
}

@test "cleanup failure fails successful run and maintenance warning stays successful" {
  run bash -c '
    source "$TASK_DIR/harness.sh"
    unset -f trap
    ensure_login_disabled() {
      [[ "$RUN_FINALIZED" -eq 0 ]]
    }
    cmd_bounded_run 0
  '
  [ "$status" -eq 1 ]
  [ "$(<"$TASK_DIR/notifications")" = failure ]
  rm -f "$TASK_DIR/notifications"
  run env TASK_MAINTENANCE_RC=9 bash -c '
    source "$TASK_DIR/harness.sh"
    unset -f trap
    cmd_bounded_run 0
  '
  [ "$status" -eq 0 ]
  [ "$(<"$TASK_DIR/notifications")" = warning ]
}
