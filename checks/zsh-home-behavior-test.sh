#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2030,SC2031 # Literal zsh program; UV cases intentionally isolate environment changes.
# Deterministic behavior checks for reviewed zsh/direnv desired state.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FKILL_SOURCE="$ROOT/rig/home/dot_zsh/functions/fkill"
LAYOUT_UV_SOURCE="$ROOT/rig/home/private_dot_config/direnv/lib/layout_uv.sh"
PNPM_COMPLETION="$ROOT/rig/home/dot_zsh/completions/_pnpm"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/zsh-home-test.XXXXXX")"

cleanup() {
  if [[ -n ${TMP:-} && -d $TMP && $TMP == "${TMPDIR:-/tmp}"/zsh-home-test.* ]]; then
    rm -rf -- "$TMP"
  fi
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

mkdir -p "$TMP/bin"
cat >"$TMP/bin/fzf" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
rc=${FKILL_FZF_RC:-0}
(( rc == 0 )) || exit "$rc"
[[ ! -s ${FKILL_SELECTION_FILE:?} ]] || /bin/cat "$FKILL_SELECTION_FILE"
STUB
chmod +x "$TMP/bin/fzf"

run_fkill() {
  env \
    PATH="$TMP/bin:$PATH" \
    FKILL_SOURCE="$FKILL_SOURCE" \
    FKILL_SELECTION_FILE="$1" \
    FKILL_KILL_LOG="$2" \
    FKILL_FZF_RC="${3:-0}" \
    FKILL_KILL_RC="${4:-0}" \
    FKILL_APPEND_SELF="${5:-0}" \
    zsh -fc '
      ps() { print -r -- "PID USER COMM ARGS"; }
      kill() {
        print -r -- "$*" >>"$FKILL_KILL_LOG"
        return "$FKILL_KILL_RC"
      }
      if [[ $FKILL_APPEND_SELF == 1 ]]; then
        print -r -- "$$ self zsh zsh" >>"$FKILL_SELECTION_FILE"
      fi
      source "$FKILL_SOURCE"
    '
}

selection="$TMP/fkill-selection"
kill_log="$TMP/fkill-kill.log"
cat >"$selection" <<'ROWS'
0 root kernel kernel_task
1 root launchd /sbin/launchd
garbage user bad bad
999999999999999999999 user huge huge
2147483648 user too-big too-big
0002 user first first
2 user duplicate duplicate
2147483647 user max max
ROWS
: >"$kill_log"
run_fkill "$selection" "$kill_log" 0 0 1 || fail "fkill rejected valid filtered selection"
[[ $(cat "$kill_log") == '-- 2 2147483647' ]] \
  || fail "fkill did not reject unsafe/self/duplicate PIDs: $(cat "$kill_log")"

: >"$selection"
: >"$kill_log"
set +e
run_fkill "$selection" "$kill_log" 130 0 0
cancel_rc=$?
set -e
[[ $cancel_rc == 130 ]] || fail "fkill cancellation status changed: $cancel_rc"
[[ ! -s $kill_log ]] || fail "fkill invoked kill after cancellation"

printf '%s\n' '42 user command args' >"$selection"
: >"$kill_log"
set +e
run_fkill "$selection" "$kill_log" 0 23 0
kill_rc=$?
set -e
[[ $kill_rc == 23 ]] || fail "fkill masked kill failure: $kill_rc"
[[ $(cat "$kill_log") == '-- 42' ]] || fail "fkill kill-failure fixture selected wrong PID"
echo "OK fkill safety/cancellation/failure"

watch_file() { :; }
has() { [[ $1 == uv ]]; }
log_error() { printf '%s\n' "$*" >&2; }
expand_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$PWD" "$1" ;;
  esac
}
PATH_add() { export PATH="$1:$PATH"; }
uv() {
  printf '%s\n' "$*" >>"$UV_CALL_LOG"
  if [[ ${UV_TEST_MODE:-ok} == fail ]]; then
    return 42
  fi
  mkdir -p "$UV_PROJECT_ENVIRONMENT/bin"
}
# shellcheck source=/dev/null
source "$LAYOUT_UV_SOURCE"

mkdir -p "$TMP/uv-existing/.venv/bin"
: >"$TMP/uv-existing/pyproject.toml"
: >"$TMP/uv-existing/uv.log"
(
  cd "$TMP/uv-existing"
  unset UV_PROJECT_ENVIRONMENT VIRTUAL_ENV
  export UV_CALL_LOG="$PWD/uv.log"
  layout_uv
  [[ $VIRTUAL_ENV == "$PWD/.venv" ]] || fail "layout_uv activated the wrong environment"
  [[ $PATH == "$PWD/.venv/bin:"* ]] || fail "layout_uv did not prepend the environment bin"
  [[ ! -s $UV_CALL_LOG ]] || fail "layout_uv invoked uv during routine activation"
)

mkdir -p "$TMP/uv-missing"
: >"$TMP/uv-missing/pyproject.toml"
: >"$TMP/uv-missing/uv.log"
set +e
missing_output=$(
  cd "$TMP/uv-missing"
  unset UV_PROJECT_ENVIRONMENT VIRTUAL_ENV
  export UV_CALL_LOG="$PWD/uv.log"
  layout_uv 2>&1
)
missing_rc=$?
set -e
[[ $missing_rc == 1 ]] || fail "layout_uv missing-environment status changed: $missing_rc"
[[ $missing_output == *layout_uv_sync* ]] || fail "layout_uv missing-environment error is not actionable"
[[ ! -s $TMP/uv-missing/uv.log ]] || fail "layout_uv synchronized a missing environment"

set +e
arg_output=$(
  cd "$TMP/uv-existing"
  unset UV_PROJECT_ENVIRONMENT VIRTUAL_ENV
  export UV_CALL_LOG="$PWD/uv.log"
  layout_uv 3.12 2>&1
)
arg_rc=$?
set -e
[[ $arg_rc == 2 ]] || fail "layout_uv accepted implicit sync arguments: $arg_rc"
[[ $arg_output == *layout_uv_sync* ]] || fail "layout_uv argument error is not actionable"
[[ ! -s $TMP/uv-existing/uv.log ]] || fail "layout_uv arguments triggered uv"

mkdir -p "$TMP/uv-sync"
: >"$TMP/uv-sync/pyproject.toml"
: >"$TMP/uv-sync/uv.log"
(
  cd "$TMP/uv-sync"
  unset UV_PROJECT_ENVIRONMENT VIRTUAL_ENV
  export UV_CALL_LOG="$PWD/uv.log"
  layout_uv_sync 3.12 --no-dev
  [[ $(cat "$UV_CALL_LOG") == 'sync --frozen --python 3.12 --no-dev' ]] \
    || fail "layout_uv_sync arguments changed: $(cat "$UV_CALL_LOG")"
  [[ $VIRTUAL_ENV == "$PWD/.venv" ]] || fail "layout_uv_sync did not activate after success"
)

mkdir -p "$TMP/uv-fail"
: >"$TMP/uv-fail/pyproject.toml"
: >"$TMP/uv-fail/uv.log"
set +e
(
  cd "$TMP/uv-fail"
  unset UV_PROJECT_ENVIRONMENT VIRTUAL_ENV
  export UV_CALL_LOG="$PWD/uv.log" UV_TEST_MODE=fail
  layout_uv_sync
)
sync_fail_rc=$?
set -e
[[ $sync_fail_rc == 42 ]] || fail "layout_uv_sync masked uv failure: $sync_fail_rc"
[[ ! -d $TMP/uv-fail/.venv ]] || fail "layout_uv_sync activated after uv failure"
echo "OK layout_uv activation-only/explicit-sync"

[[ -f $PNPM_COMPLETION ]] || fail "tracked _pnpm completion missing"
generator_version=$(sed -n 's/^# Generated by pnpm \([^ ]*\) via:.*/\1/p' "$PNPM_COMPLETION")
[[ -n $generator_version ]] || fail "_pnpm generator version missing"
grep -Fqx '#compdef pnpm' "$PNPM_COMPLETION" || fail "_pnpm compdef missing"

completion_line=$(grep -nF '$HOME/.zsh/completions(N)' "$ROOT/rig/dots/zshrc" | head -1 | cut -d: -f1)
omz_line=$(grep -n 'oh-my-zsh.sh' "$ROOT/rig/dots/zshrc" | head -1 | cut -d: -f1)
((completion_line < omz_line)) || fail "managed completion fpath follows Oh My Zsh"

pnpm_generator=()
if command -v pnpm >/dev/null 2>&1 && [[ $(pnpm --version) == "$generator_version" ]]; then
  pnpm_generator=(pnpm)
elif command -v mise >/dev/null 2>&1 && mise where "pnpm@$generator_version" >/dev/null 2>&1; then
  pnpm_generator=(mise x "pnpm@$generator_version" -- pnpm)
fi

if ((${#pnpm_generator[@]})); then
  actual_version=$("${pnpm_generator[@]}" --version)
  [[ $actual_version == "$generator_version" ]] || fail "resolved pnpm generator version changed: $actual_version"
  generated_raw="$TMP/_pnpm.generated.raw"
  generated="$TMP/_pnpm.generated"
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout 30s "${pnpm_generator[@]}" completion zsh >"$generated_raw"
  else
    "${pnpm_generator[@]}" completion zsh >"$generated_raw"
  fi
  # pnpm emits one presentation-only blank line after its end marker.
  sed '${/^$/d;}' "$generated_raw" >"$generated"
  tail -n +3 "$PNPM_COMPLETION" >"$TMP/_pnpm.expected"
  cmp -s "$generated" "$TMP/_pnpm.expected" || fail "tracked _pnpm differs from pnpm $generator_version output"
  echo "OK pnpm completion reproducible ($generator_version)"
else
  echo "SKIP pnpm completion regeneration (pnpm $generator_version unavailable); static contract passed"
fi
