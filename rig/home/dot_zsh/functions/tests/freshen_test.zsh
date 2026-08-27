#!/usr/bin/env zsh

emulate -L zsh
setopt PIPE_FAIL

TEST_SCRIPT_DIR="${0:A:h}"
FRESHEN_FILE="${FRESHEN_UNDER_TEST:-${TEST_SCRIPT_DIR:h}/freshen}"
FRESHEN_FILE="${FRESHEN_FILE:A}"
FRESHEN_DIR="${FRESHEN_FILE:h}"
TEST_BASE_TMP="${TMPDIR:-/tmp}"

if [[ ! -r "$FRESHEN_FILE" ]]; then
    print -u2 -r -- "freshen under test is not readable: ${FRESHEN_FILE}"
    exit 2
fi

integer TESTS_RUN=0
integer TESTS_FAILED=0
typeset -ga TEST_ROOTS=()

cleanup_test_roots() {
    [[ "${FRESHEN_TEST_KEEP_TMP:-0}" == "1" ]] && return

    local test_root
    for test_root in "${TEST_ROOTS[@]}"; do
        [[ -n "$test_root" && -d "$test_root" ]] && rm -rf -- "$test_root"
    done
}

TRAPEXIT() {
    cleanup_test_roots
}

pass() {
    TESTS_RUN+=1
    print "ok ${TESTS_RUN} - $1"
}

fail() {
    TESTS_RUN+=1
    TESTS_FAILED+=1
    print -u2 -r -- "not ok ${TESTS_RUN} - $1"
}

assert_contains() {
    local file="$1" needle="$2" label="$3"
    if grep -Fq -- "$needle" "$file"; then
        pass "$label"
    else
        print -u2 -r -- "expected to find: $needle"
        print -u2 -r -- "--- file: $file ---"
        sed -n '1,220p' "$file" >&2
        fail "$label"
    fi
}

assert_not_contains() {
    local file="$1" needle="$2" label="$3"
    if grep -Fq -- "$needle" "$file"; then
        print -u2 -r -- "did not expect to find: $needle"
        print -u2 -r -- "--- file: $file ---"
        sed -n '1,220p' "$file" >&2
        fail "$label"
    else
        pass "$label"
    fi
}

assert_status() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$label"
    else
        print -u2 -r -- "expected status $expected, got $actual"
        fail "$label"
    fi
}

assert_interrupt_status() {
    local actual="$1" label="$2"
    if [[ "$actual" == 130 || "$actual" == 143 ]]; then
        pass "$label"
    else
        print -u2 -r -- "expected interrupt status 130 or 143, got $actual"
        fail "$label"
    fi
}

assert_trace_order() {
    local first="$1" second="$2" label="$3"
    local first_line second_line
    first_line=$(grep -nF -- "$first" "$TRACE_FILE" | sed -n '1s/:.*//p')
    second_line=$(grep -nF -- "$second" "$TRACE_FILE" | sed -n '1s/:.*//p')
    if [[ -n "$first_line" && -n "$second_line" && "$first_line" -lt "$second_line" ]]; then
        pass "$label"
    else
        print -u2 -r -- "--- trace ---"
        sed -n '1,160p' "$TRACE_FILE" >&2
        fail "$label"
    fi
}

setup_env() {
    local name="$1"
    TEST_ROOT="$(mktemp -d "${TEST_BASE_TMP}/freshen-test.${name}.XXXXXX")"
    TEST_ROOTS+=("$TEST_ROOT")
    TEST_HOME="${TEST_ROOT}/home"
    TEST_BIN="${TEST_ROOT}/bin"
    TEST_STATE="${TEST_ROOT}/state"
    TEST_TMP="${TEST_ROOT}/tmp"
    TRACE_FILE="${TEST_ROOT}/trace.log"
    mkdir -p "$TEST_HOME" "$TEST_BIN" "$TEST_STATE" "$TEST_TMP" "$TEST_HOME/.cargo/registry/cache"
    : >| "$TRACE_FILE"

    export HOME="$TEST_HOME"
    export XDG_STATE_HOME="$TEST_STATE"
    export TMPDIR="$TEST_TMP"
    export TRACE_FILE

    local key
    for key in ${(k)parameters[(I)BREW_*]}; do
        unset "$key"
    done
    for key in ${(k)parameters[(I)MAS_*]}; do
        unset "$key"
    done
    for key in ${(k)parameters[(I)STUB_*]}; do
        unset "$key"
    done
    for key in ${(k)parameters[(I)FRESHEN_*]}; do
        [[ "$key" == "FRESHEN_DIR" || "$key" == "FRESHEN_FILE" || "$key" == "FRESHEN_UNDER_TEST" || "$key" == "FRESHEN_TEST_KEEP_TMP" ]] && continue
        unset "$key"
    done
    unset BUN_INSTALL_CACHE_DIR
    unset SUDO_RC GOMI_RC

    write_brew_stub
    write_mas_stub
    write_sudo_stub
    write_tool_stub npm
    write_tool_stub pnpm
    write_tool_stub yarn
    write_tool_stub bun
    write_tool_stub uv
    write_tool_stub pip
    write_tool_stub cargo
    write_tool_stub cargo-cache
    write_tool_stub go
    write_tool_stub gem
    write_docker_stub
}

# Portable mtime stamp for age-gated --dev-prune fixtures (BSD + GNU).
freshen_stamp_mtime_days_ago() {
    local path="$1" days="$2"
    local py touch_bin date_bin
    py="$(command -v python3 2>/dev/null || true)"
    if [[ -z "$py" && -x /usr/bin/python3 ]]; then
        py="/usr/bin/python3"
    fi
    if [[ -n "$py" ]] && "$py" -c 'import os, sys, time; p, d = sys.argv[1], int(sys.argv[2]); t = time.time() - d * 86400; os.utime(p, (t, t))' "$path" "$days"; then
        :
    else
        touch_bin="/usr/bin/touch"
        [[ -x "$touch_bin" ]] || touch_bin="/bin/touch"
        date_bin="/bin/date"
        [[ -x "$date_bin" ]] || date_bin="date"
        if "$date_bin" -v-1d +%s >/dev/null 2>&1; then
            "$touch_bin" -t "$("$date_bin" -v-${days}d +%Y%m%d%H%M)" "$path" || return 1
        else
            "$touch_bin" -d "${days} days ago" "$path" || return 1
        fi
    fi
    if [[ -n "$py" ]]; then
        "$py" -c 'import os, sys, time; p, d = sys.argv[1], int(sys.argv[2]); age = (time.time() - os.stat(p).st_mtime) / 86400; sys.exit(0 if age >= d - 0.5 else 1)' "$path" "$days" || return 1
    fi
    return 0
}

run_freshen_in() {
    local cwd="$1"
    local output_file="$2"
    shift 2
    local rc=0
    (
        cd -- "$cwd" || exit 2
        PATH="${TEST_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
        HOME="${TEST_HOME}" \
        XDG_STATE_HOME="${TEST_STATE}" \
        TMPDIR="${TEST_TMP}" \
        TRACE_FILE="${TRACE_FILE}" \
        zsh -fc 'fpath=("$1" $fpath); autoload -Uz freshen; shift; freshen "$@"' zsh "$FRESHEN_DIR" "$@"
    ) >"$output_file" 2>&1 || rc=$?
    return "$rc"
}

write_tool_stub() {
    local name="$1"
    cat > "${TEST_BIN}/${name}" <<'EOF'
#!/usr/bin/env zsh
emulate -L zsh
setopt PIPE_FAIL
name="${0:t}"
upper="${(U)${name//-/_}}"
print -r -- "${name} $*" >> "${TRACE_FILE}"
sleep_var="STUB_SLEEP_${upper}"
rc_var="STUB_RC_${upper}"
out_var="STUB_STDOUT_${upper}"
err_var="STUB_STDERR_${upper}"
if [[ -n "${(P)sleep_var:-}" ]]; then
    sleep "${(P)sleep_var}"
fi
[[ -n "${(P)out_var:-}" ]] && print -r -- "${(P)out_var}"
[[ -n "${(P)err_var:-}" ]] && print -u2 -r -- "${(P)err_var}"
exit "${${(P)rc_var}:-0}"
EOF
    chmod +x "${TEST_BIN}/${name}"
}

write_brew_stub() {
    cat > "${TEST_BIN}/brew" <<'EOF'
#!/usr/bin/env zsh
emulate -L zsh
setopt PIPE_FAIL

trace() {
    print -r -- "brew $*" >> "${TRACE_FILE}"
}

pkg_key() {
    local raw="$1"
    raw="${raw//[^A-Za-z0-9]/_}"
    print -r -- "${(U)raw}"
}

trace "$@"

case "$1" in
    update)
        [[ -n "${BREW_UPDATE_SLEEP:-}" ]] && sleep "${BREW_UPDATE_SLEEP}"
        [[ -n "${BREW_UPDATE_OUTPUT:-}" ]] && print -r -- "${BREW_UPDATE_OUTPUT}"
        [[ -n "${BREW_UPDATE_STDERR:-}" ]] && print -u2 -r -- "${BREW_UPDATE_STDERR}"
        exit "${BREW_UPDATE_RC:-0}"
        ;;
    outdated)
        if [[ "$2" == "--formula" ]]; then
            local fcount_file="${TMPDIR:-/tmp}/brew_outdated_formulae_calls"
            local fcall=1
            [[ -r "$fcount_file" ]] && fcall=$(( $(<"$fcount_file") + 1 ))
            print -r -- "$fcall" >| "$fcount_file"
            [[ -n "${BREW_FORMULAE_OUTDATED_PID_FILE:-}" ]] && print -r -- "$$" >| "${BREW_FORMULAE_OUTDATED_PID_FILE}"
            [[ -n "${BREW_OUTDATED_FORMULAE_SLEEP:-}" ]] && sleep "${BREW_OUTDATED_FORMULAE_SLEEP}"
            if (( fcall > 1 )) && [[ -n "${BREW_OUTDATED_FORMULAE_LATER+x}" ]]; then
                [[ -n "${BREW_OUTDATED_FORMULAE_LATER:-}" ]] && print -r -- "${BREW_OUTDATED_FORMULAE_LATER}"
                exit "${BREW_OUTDATED_FORMULAE_LATER_RC:-0}"
            fi
            [[ -n "${BREW_OUTDATED_FORMULAE:-}" ]] && print -r -- "${BREW_OUTDATED_FORMULAE}"
            [[ -n "${BREW_OUTDATED_FORMULAE_ERR:-}" ]] && print -u2 -r -- "${BREW_OUTDATED_FORMULAE_ERR}"
            exit "${BREW_OUTDATED_FORMULAE_RC:-0}"
        fi
        if [[ "$2" == "--cask" ]]; then
            local ccount_file="${TMPDIR:-/tmp}/brew_outdated_casks_calls"
            local ccall=1
            [[ -r "$ccount_file" ]] && ccall=$(( $(<"$ccount_file") + 1 ))
            print -r -- "$ccall" >| "$ccount_file"
            [[ -n "${BREW_CASK_OUTDATED_PID_FILE:-}" ]] && print -r -- "$$" >| "${BREW_CASK_OUTDATED_PID_FILE}"
            [[ -n "${BREW_OUTDATED_CASKS_SLEEP:-}" ]] && sleep "${BREW_OUTDATED_CASKS_SLEEP}"
            if (( ccall > 1 )) && [[ -n "${BREW_OUTDATED_CASKS_LATER+x}" ]]; then
                [[ -n "${BREW_OUTDATED_CASKS_LATER:-}" ]] && print -r -- "${BREW_OUTDATED_CASKS_LATER}"
                exit "${BREW_OUTDATED_CASKS_LATER_RC:-0}"
            fi
            [[ -n "${BREW_OUTDATED_CASKS:-}" ]] && print -r -- "${BREW_OUTDATED_CASKS}"
            [[ -n "${BREW_OUTDATED_CASKS_ERR:-}" ]] && print -u2 -r -- "${BREW_OUTDATED_CASKS_ERR}"
            exit "${BREW_OUTDATED_CASKS_RC:-0}"
        fi
        ;;
    upgrade)
        if [[ "$2" == "--cask" ]]; then
            shift 2
            [[ "$1" == "--greedy" ]] && shift
            if (( $# > 1 )); then
                [[ -n "${BREW_CASK_UPGRADE_OUTPUT:-}" ]] && print -r -- "${BREW_CASK_UPGRADE_OUTPUT}"
                [[ -n "${BREW_CASK_UPGRADE_STDERR:-}" ]] && print -u2 -r -- "${BREW_CASK_UPGRADE_STDERR}"
                exit "${BREW_CASK_UPGRADE_RC:-0}"
            fi
            key="$(pkg_key "$1")"
            sleep_var="BREW_CASK_SINGLE_SLEEP_${key}"
            out_var="BREW_CASK_SINGLE_OUTPUT_${key}"
            err_var="BREW_CASK_SINGLE_STDERR_${key}"
            rc_var="BREW_CASK_SINGLE_RC_${key}"
            [[ -n "${(P)sleep_var:-}" ]] && sleep "${(P)sleep_var}"
            [[ -n "${(P)out_var:-}" ]] && print -r -- "${(P)out_var}"
            [[ -n "${(P)err_var:-}" ]] && print -u2 -r -- "${(P)err_var}"
            exit "${${(P)rc_var}:-0}"
        fi

        shift
        if (( $# > 1 )); then
            [[ -n "${BREW_FORMULA_UPGRADE_OUTPUT:-}" ]] && print -r -- "${BREW_FORMULA_UPGRADE_OUTPUT}"
            [[ -n "${BREW_FORMULA_UPGRADE_STDERR:-}" ]] && print -u2 -r -- "${BREW_FORMULA_UPGRADE_STDERR}"
            exit "${BREW_FORMULA_UPGRADE_RC:-0}"
        fi
        key="$(pkg_key "$1")"
        sleep_var="BREW_FORMULA_SINGLE_SLEEP_${key}"
        out_var="BREW_FORMULA_SINGLE_OUTPUT_${key}"
        err_var="BREW_FORMULA_SINGLE_STDERR_${key}"
        rc_var="BREW_FORMULA_SINGLE_RC_${key}"
        [[ -n "${(P)sleep_var:-}" ]] && sleep "${(P)sleep_var}"
        [[ -n "${(P)out_var:-}" ]] && print -r -- "${(P)out_var}"
        [[ -n "${(P)err_var:-}" ]] && print -u2 -r -- "${(P)err_var}"
        exit "${${(P)rc_var}:-0}"
        ;;
    autoremove)
        [[ -n "${BREW_AUTOREMOVE_OUTPUT:-}" ]] && print -r -- "${BREW_AUTOREMOVE_OUTPUT}"
        [[ -n "${BREW_AUTOREMOVE_STDERR:-}" ]] && print -u2 -r -- "${BREW_AUTOREMOVE_STDERR}"
        exit "${BREW_AUTOREMOVE_RC:-0}"
        ;;
    cleanup)
        [[ -n "${BREW_CLEANUP_OUTPUT:-}" ]] && print -r -- "${BREW_CLEANUP_OUTPUT}"
        [[ -n "${BREW_CLEANUP_STDERR:-}" ]] && print -u2 -r -- "${BREW_CLEANUP_STDERR}"
        exit "${BREW_CLEANUP_RC:-0}"
        ;;
    doctor)
        [[ -n "${BREW_DOCTOR_OUTPUT:-}" ]] && print -r -- "${BREW_DOCTOR_OUTPUT}"
        [[ -n "${BREW_DOCTOR_STDERR:-}" ]] && print -u2 -r -- "${BREW_DOCTOR_STDERR}"
        exit "${BREW_DOCTOR_RC:-0}"
        ;;
    info)
        if [[ " $* " == *" --json=v2 "* ]] && [[ " $* " == *" --cask "* ]]; then
            [[ -n "${BREW_CASK_INFO_SLEEP:-}" ]] && sleep "${BREW_CASK_INFO_SLEEP}"
            if [[ -n "${BREW_CASK_INFO_JSON+x}" ]]; then
                [[ -n "${BREW_CASK_INFO_JSON:-}" ]] && print -r -- "${BREW_CASK_INFO_JSON}"
            else
                print -r -- '{"casks":[]}'
            fi
            [[ -n "${BREW_CASK_INFO_STDERR:-}" ]] && print -u2 -r -- "${BREW_CASK_INFO_STDERR}"
            exit "${BREW_CASK_INFO_RC:-0}"
        fi
        ;;
    --version)
        print "Homebrew test"
        exit 0
        ;;
esac

print -u2 -r -- "unexpected brew invocation: $*"
exit 99
EOF
    chmod +x "${TEST_BIN}/brew"
}

write_mas_stub() {
    cat > "${TEST_BIN}/mas" <<'EOF'
#!/usr/bin/env zsh
emulate -L zsh

print -r -- "mas $*" >> "${TRACE_FILE}"
[[ -n "${MAS_PID_FILE:-}" ]] && print -r -- "$$" >| "${MAS_PID_FILE}"

case "$1" in
    outdated)
        [[ -n "${MAS_OUTDATED_SLEEP:-}" ]] && sleep "${MAS_OUTDATED_SLEEP}"
        [[ -n "${MAS_OUTDATED:-}" ]] && print -r -- "${MAS_OUTDATED}"
        [[ -n "${MAS_OUTDATED_STDERR:-}" ]] && print -u2 -r -- "${MAS_OUTDATED_STDERR}"
        exit "${MAS_OUTDATED_RC:-0}"
        ;;
    update)
        [[ -n "${MAS_UPDATE_SLEEP:-}" ]] && sleep "${MAS_UPDATE_SLEEP}"
        [[ -n "${MAS_UPDATE_OUTPUT:-}" ]] && print -r -- "${MAS_UPDATE_OUTPUT}"
        [[ -n "${MAS_UPDATE_STDERR:-}" ]] && print -u2 -r -- "${MAS_UPDATE_STDERR}"
        exit "${MAS_UPDATE_RC:-0}"
        ;;
    account)
        [[ -n "${MAS_ACCOUNT_OUTPUT:-}" ]] && print -r -- "${MAS_ACCOUNT_OUTPUT}"
        [[ -n "${MAS_ACCOUNT_STDERR:-}" ]] && print -u2 -r -- "${MAS_ACCOUNT_STDERR}"
        exit "${MAS_ACCOUNT_RC:-0}"
        ;;
    version|--version)
        print "mas test"
        exit 0
        ;;
esac

print -u2 -r -- "unexpected mas invocation: $*"
exit 98
EOF
    chmod +x "${TEST_BIN}/mas"
}

write_sudo_stub() {
    cat > "${TEST_BIN}/sudo" <<'EOF'
#!/usr/bin/env zsh
emulate -L zsh

print -r -- "sudo $*" >> "${TRACE_FILE}"
exit "${SUDO_RC:-0}"
EOF
    chmod +x "${TEST_BIN}/sudo"
}

write_gomi_stub() {
    cat > "${TEST_BIN}/gomi" <<'EOF'
#!/usr/bin/env zsh
emulate -L zsh

print -r -- "gomi $*" >> "${TRACE_FILE}"
exit "${GOMI_RC:-0}"
EOF
    chmod +x "${TEST_BIN}/gomi"
}

write_docker_stub() {
    cat > "${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env zsh
emulate -L zsh

print -r -- "docker $*" >> "${TRACE_FILE}"

case "$1" in
    info)
        exit "${STUB_DOCKER_INFO_RC:-1}"
        ;;
    system)
        shift
        [[ "$1" == "prune" ]] && exit "${STUB_DOCKER_PRUNE_RC:-0}"
        ;;
esac

exit "${STUB_DOCKER_RC:-0}"
EOF
    chmod +x "${TEST_BIN}/docker"
}

run_freshen() {
    local output_file="$1"
    shift
    local rc=0
    PATH="${TEST_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="${TEST_HOME}" \
    XDG_STATE_HOME="${TEST_STATE}" \
    TMPDIR="${TEST_TMP}" \
    TRACE_FILE="${TRACE_FILE}" \
    FRESHEN_UNDER_TEST="${FRESHEN_UNDER_TEST:-$FRESHEN_FILE}" \
    zsh -fc 'fpath=("$1" $fpath); autoload -Uz freshen; shift; freshen "$@"' zsh "$FRESHEN_DIR" "$@" >"$output_file" 2>&1 || rc=$?
    return "$rc"
}

# Same-process hygiene probe: the probe zsh IS the process under test (not nested zsh -fc freshen alone).
# Writes LEAK lines for residual nested helpers / global _batch_status after freshen returns.
run_freshen_hygiene_probe() {
    local output_file="$1"
    shift
    local probe="${TEST_ROOT}/hygiene-probe.zsh"
    local rc=0
    cat >| "$probe" <<EOF
emulate -L zsh
setopt PIPE_FAIL
fpath=("$FRESHEN_DIR" \$fpath)
autoload -Uz freshen
freshen "\$@" >/dev/null 2>&1 || true
local -a watch=(
  _err _warn _run_with_timeout _classify_batch_items _prepare_sudo_for_casks
  _positive_int_env _set_phase _emit_phase __freshen_teardown
  _mtime_epoch _is_live_workspace_dir _print_backup_status _run_report_cmd
  _live_enter _live_leave _live_begin _live_pause_for_prompt _live_resume _live_abort_dashboard
)
local name
for name in \$watch; do
  if whence -w "\$name" 2>/dev/null | grep -q 'function'; then
    print -r -- "LEAK \$name"
  fi
done
if typeset -p _batch_status >/dev/null 2>&1; then
  print -r -- "LEAK _batch_status"
fi
EOF
    PATH="${TEST_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="${TEST_HOME}" \
    XDG_STATE_HOME="${TEST_STATE}" \
    TMPDIR="${TEST_TMP}" \
    TRACE_FILE="${TRACE_FILE}" \
    FRESHEN_UNDER_TEST="${FRESHEN_UNDER_TEST:-$FRESHEN_FILE}" \
    zsh "$probe" "$@" >"$output_file" 2>&1 || rc=$?
    return "$rc"
}

find_log_path() {
    local output_file="$1"
    sed -n 's/^  Log: //p' "$output_file" | tail -1
}

test_help_and_version() {
    setup_env help
    local help_out="${TEST_ROOT}/help.out"
    local version_out="${TEST_ROOT}/version.out"

    run_freshen "$help_out" --help --no-color
    assert_status 0 $? "help exits cleanly"
    assert_contains "$help_out" "Inventory only; show the plan and make no changes" "help documents dry-run behavior"
    assert_contains "$help_out" "CAPITAL SHORTCUTS" "help has a dedicated capital shortcut section"
    assert_contains "$help_out" "-D  --doctor" "help documents doctor shorthand"
    assert_contains "$help_out" "-C  --clean-only" "help documents clean-only shorthand"
    assert_contains "$help_out" "SAFE FIRST RUN" "help includes safe first run guidance"
    assert_contains "$help_out" "AUTOMATION" "help includes automation guidance"
    assert_contains "$help_out" "ENVIRONMENT" "help documents environment tuning knobs"
    assert_contains "$help_out" "EXIT CODES" "help documents exit code meanings"
    assert_contains "$help_out" "--clean-only" "help documents clean-only mode"
    assert_contains "$help_out" "--progress=MODE" "help documents progress mode selection"
    assert_contains "$help_out" "--no-sudo-preflight" "help documents sudo preflight override"

    run_freshen "$version_out" --version --no-color
    assert_status 0 $? "version exits cleanly"
    assert_contains "$version_out" "freshen 1.11.0" "version reports new release"
}

test_capital_shorthands() {
    setup_env capital-shorthands
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_FORMULA_SINGLE_OUTPUT_ALPHA=$'==> Upgrading alpha\nalpha 1.0 -> 1.1'
    local out="${TEST_ROOT}/capital-shorthands.out"

    run_freshen "$out" -N -Y -M -A --no-color
    assert_status 0 $? "-N -Y -M -A dry-run shorthand exits cleanly"
    assert_contains "$out" "Dry run: inventory only, no changes made" "-N enables dry-run"
    assert_not_contains "$TRACE_FILE" "mas outdated" "-M disables App Store inventory"
    assert_not_contains "$TRACE_FILE" "npm cache clean --force" "-A disables cache cleaning"

    : >| "$TRACE_FILE"
    run_freshen "$out" -C -Y -B -A --no-color
    assert_status 0 $? "-C -Y -B -A clean-only shorthand exits cleanly"
    assert_contains "$out" "Mode: clean-only" "-C enables clean-only mode"
    assert_not_contains "$TRACE_FILE" "brew autoremove" "-B disables cleanup"
    assert_not_contains "$TRACE_FILE" "npm cache clean --force" "-A disables cache cleaning"

    : >| "$TRACE_FILE"
    run_freshen "$out" -F -Y -M -B -A --no-color
    assert_status 0 $? "-F formula-only shorthand exits cleanly"
    assert_contains "$out" "Casks: skipped — disabled by --formula-only" "-F maps to formula-only"

    : >| "$TRACE_FILE"
    export BREW_OUTDATED_FORMULAE=''
    export BREW_OUTDATED_CASKS='firefox'
    export BREW_CASK_SINGLE_OUTPUT_FIREFOX=$'==> Upgrading Cask firefox\nfirefox: 1.0 -> 1.1'
    run_freshen "$out" -K -Y -M -B -A --no-sudo-preflight --no-color
    assert_status 0 $? "-K cask-only shorthand exits cleanly"
    assert_contains "$out" "Formulae: skipped — disabled by --cask-only" "-K maps to cask-only"
    assert_contains "$TRACE_FILE" "brew upgrade --cask" "-K runs cask lane"

    : >| "$TRACE_FILE"
    run_freshen "$out" -D -Y -M -B -A --no-color
    assert_status 0 $? "-D doctor shorthand exits cleanly"
    assert_contains "$TRACE_FILE" "brew doctor" "-D runs brew doctor"
}

test_clean_only_dry_run_skips_inventory() {
    setup_env clean-only
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_OUTDATED_CASKS='firefox'
    export MAS_OUTDATED='1234 OneApp'
    local out="${TEST_ROOT}/clean-only.out"

    run_freshen "$out" --clean-only --dry-run --yes --progress=plain --no-color
    assert_status 0 $? "clean-only dry-run exits cleanly"
    assert_contains "$out" "Mode: clean-only" "clean-only plan labels clean-only mode"
    assert_contains "$out" "Cleanup:" "clean-only plan includes cleanup lane"
    assert_contains "$out" "Caches:" "clean-only plan includes cache lane"
    assert_contains "$out" "Clean-only dry run: no changes made" "clean-only dry-run announces no mutation"
    assert_not_contains "$out" "Outdated" "clean-only dry-run does not render upgrade inventory"
    assert_not_contains "$TRACE_FILE" "brew update" "clean-only dry-run skips brew update"
    assert_not_contains "$TRACE_FILE" "brew outdated" "clean-only dry-run skips brew inventory"
    assert_not_contains "$TRACE_FILE" "mas outdated" "clean-only dry-run skips App Store inventory"
    assert_not_contains "$TRACE_FILE" "brew autoremove" "clean-only dry-run skips cleanup mutation"
    assert_not_contains "$TRACE_FILE" "npm cache clean --force" "clean-only dry-run skips cache mutation"
}

test_clean_only_executes_cleanup_and_caches_without_inventory() {
    setup_env clean-only-execute
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_OUTDATED_CASKS='firefox'
    export MAS_OUTDATED='1234 OneApp'
    local out="${TEST_ROOT}/clean-only-execute.out"

    run_freshen "$out" --clean-only --yes --progress=plain --no-color
    assert_status 0 $? "clean-only execute exits cleanly"
    assert_contains "$TRACE_FILE" "brew autoremove" "clean-only execute runs brew autoremove"
    assert_contains "$TRACE_FILE" "brew cleanup -s" "clean-only execute runs brew cleanup"
    assert_contains "$TRACE_FILE" "npm cache clean --force" "clean-only execute runs cache cleanup"
    assert_not_contains "$TRACE_FILE" "brew update" "clean-only execute skips brew update"
    assert_not_contains "$TRACE_FILE" "brew outdated" "clean-only execute skips brew inventory"
    assert_not_contains "$TRACE_FILE" "brew upgrade" "clean-only execute skips brew upgrades"
    assert_not_contains "$TRACE_FILE" "mas outdated" "clean-only execute skips App Store inventory"
    assert_not_contains "$TRACE_FILE" "mas update" "clean-only execute skips App Store updates"
}

test_clean_only_cache_only_does_not_require_brew() {
    setup_env clean-only-no-brew
    command rm -f "${TEST_BIN}/brew"
    local out="${TEST_ROOT}/clean-only-no-brew.out"

    run_freshen "$out" --clean-only --yes --no-cleanup --progress=plain --no-color
    assert_status 0 $? "clean-only cache-only works without brew"
    assert_contains "$TRACE_FILE" "npm cache clean --force" "clean-only cache-only still runs cache cleanup"
    assert_not_contains "$out" "Homebrew not found" "clean-only cache-only does not require Homebrew"
}

test_noninteractive_requires_yes() {
    setup_env noyes
    local out="${TEST_ROOT}/noyes.out"

    run_freshen "$out" --no-color
    assert_status 1 $? "non-interactive run without --yes fails"
    assert_contains "$out" "Non-interactive — use --yes to proceed" "non-interactive failure is explicit"
}

test_quiet_does_not_imply_yes() {
    setup_env quiet-no-yes
    local out="${TEST_ROOT}/quiet-no-yes.out"

    run_freshen "$out" --quiet --no-color
    assert_status 1 $? "quiet non-interactive run without --yes fails"
    assert_not_contains "$TRACE_FILE" "brew update" "quiet without yes does not refresh Homebrew metadata"
    assert_not_contains "$TRACE_FILE" "mas outdated" "quiet without yes does not query App Store inventory"
    assert_not_contains "$TRACE_FILE" "brew autoremove" "quiet without yes does not start cleanup"
    assert_not_contains "$TRACE_FILE" "npm cache clean --force" "quiet without yes does not start cache cleanup"
}

test_dry_run_is_inventory_only() {
    setup_env dryrun
    export BREW_OUTDATED_FORMULAE=$'alpha\nbeta'
    export BREW_OUTDATED_CASKS='firefox'
    export MAS_OUTDATED='1234 OneApp'
    local out="${TEST_ROOT}/dryrun.out"

    run_freshen "$out" --dry-run --yes --no-color
    assert_status 0 $? "dry-run exits cleanly"
    assert_contains "$out" "Dry run: inventory only, no changes made" "dry-run announces no mutation"
    assert_contains "$TRACE_FILE" "brew update" "dry-run still refreshes inventory"
    assert_contains "$TRACE_FILE" "brew outdated --formula --quiet" "dry-run checks formulae"
    assert_contains "$TRACE_FILE" "brew outdated --cask --greedy --quiet" "dry-run checks casks"
    assert_contains "$TRACE_FILE" "mas outdated" "dry-run checks App Store inventory"
    assert_not_contains "$TRACE_FILE" "brew upgrade" "dry-run does not upgrade brew packages"
    assert_not_contains "$TRACE_FILE" "brew autoremove" "dry-run does not clean up brew"
    assert_not_contains "$TRACE_FILE" "mas update" "dry-run does not update App Store apps"
    assert_not_contains "$TRACE_FILE" "npm cache clean --force" "dry-run does not clean caches"
}

test_storage_plan_is_read_only_without_brew() {
    setup_env storage-plan
    command rm -f "${TEST_BIN}/brew"
    local out="${TEST_ROOT}/storage-plan.out"

    run_freshen "$out" --storage-plan --restore-target-gib=170 --no-color
    assert_status 0 $? "storage-plan works without Homebrew"
    assert_contains "$out" "freshen storage plan" "storage-plan prints report title"
    assert_contains "$out" "Free Space" "storage-plan prints free-space section"
    assert_contains "$out" "Large Local Surfaces" "storage-plan prints surface section"
    assert_contains "$out" "Regenerable Dev Dirs" "storage-plan prints dev-prune section"
    assert_not_contains "$TRACE_FILE" "brew " "storage-plan does not invoke brew"
    assert_not_contains "$TRACE_FILE" "mas " "storage-plan does not invoke mas"
    assert_not_contains "$TRACE_FILE" "npm cache clean --force" "storage-plan does not clean caches"
}

test_invalid_restore_target_warns_without_mutation() {
    setup_env invalid-restore-target
    local out="${TEST_ROOT}/invalid-restore-target.out"

    run_freshen "$out" --storage-plan --restore-target-gib=abc --no-color
    assert_status 0 $? "invalid restore target remains read-only"
    assert_contains "$out" "--restore-target-gib must be a positive integer: abc" "invalid restore target warning is explicit"
    assert_not_contains "$TRACE_FILE" "brew " "invalid restore target does not invoke brew"
}

test_no_greedy_shorthand_cask_invocation() {
    setup_env no-greedy-cask
    export BREW_OUTDATED_CASKS='firefox'
    export BREW_CASK_SINGLE_OUTPUT_FIREFOX=$'==> Upgrading Cask firefox\nfirefox: 1.0 -> 1.1'
    local out="${TEST_ROOT}/no-greedy-cask.out"

    run_freshen "$out" -K -G -Y -M -B -A --no-sudo-preflight --no-color
    assert_status 0 $? "-G cask upgrade exits cleanly"
    assert_contains "$TRACE_FILE" "brew outdated --cask --quiet" "-G checks casks without --greedy"
    assert_contains "$TRACE_FILE" "brew upgrade --cask firefox" "-G upgrades casks without --greedy"
    assert_not_contains "$TRACE_FILE" "--greedy" "-G removes all --greedy cask flags"
}

test_batch_unknown_classification_degrades() {
    setup_env batch-unknown
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_FORMULA_UPGRADE_OUTPUT='Pouring unrelated bottle output'
    local out="${TEST_ROOT}/batch-unknown.out"

    run_freshen "$out" -Y -M -B -A --no-color
    assert_status 1 $? "unresolved batch formula returns non-zero"
    assert_contains "$out" "Formulae: degraded — attempted 1, confirmed 0, unresolved 1" "unrecognized batch output is unresolved"
}

test_cleanup_degraded_paths() {
    setup_env cleanup-degraded
    export BREW_AUTOREMOVE_RC=2
    local out="${TEST_ROOT}/cleanup-degraded.out"

    run_freshen "$out" -C -Y -A --no-color
    assert_status 1 $? "autoremove failure degrades cleanup"
    assert_contains "$out" "Cleanup: degraded" "autoremove failure reports degraded cleanup"
    assert_not_contains "$TRACE_FILE" "brew cleanup -s" "cleanup -s is skipped after autoremove failure"

    setup_env cleanup-second-step-degraded
    export BREW_CLEANUP_RC=3
    out="${TEST_ROOT}/cleanup-second-step-degraded.out"
    run_freshen "$out" -C -Y -A --no-color
    assert_status 1 $? "brew cleanup failure degrades cleanup"
    assert_contains "$out" "Cleanup: degraded" "brew cleanup failure reports degraded cleanup"
    assert_contains "$TRACE_FILE" "brew autoremove" "brew cleanup failure first runs autoremove"
    assert_contains "$TRACE_FILE" "brew cleanup -s" "brew cleanup failure runs cleanup step"
    assert_trace_order "brew autoremove" "brew cleanup -s" "autoremove precedes cleanup -s"
}

test_doctor_lane_success_and_failure() {
    setup_env doctor-success
    local out="${TEST_ROOT}/doctor-success.out"

    run_freshen "$out" -D -Y -M -B -A --no-color
    assert_status 0 $? "doctor success exits cleanly"
    assert_contains "$out" "Doctor: done — system healthy" "doctor success reports healthy"

    setup_env doctor-failure
    export BREW_DOCTOR_RC=2
    out="${TEST_ROOT}/doctor-failure.out"
    run_freshen "$out" -D -Y -M -B -A --no-color
    assert_status 1 $? "doctor failure returns non-zero"
    assert_contains "$out" "Doctor: degraded — brew doctor reported issues" "doctor failure reports degraded"
}

test_default_run_requires_brew_but_storage_plan_does_not() {
    setup_env missing-brew
    command rm -f "${TEST_BIN}/brew"
    local out="${TEST_ROOT}/missing-brew.out"

    run_freshen "$out" -Y --no-color
    assert_status 127 $? "default run without brew returns 127"
    assert_contains "$out" "Homebrew not found" "missing brew message is explicit"

    : >| "$TRACE_FILE"
    run_freshen "$out" -S --no-color
    assert_status 0 $? "storage-plan shorthand works without brew"
    assert_contains "$out" "freshen storage plan" "storage-plan shorthand prints report"
    assert_not_contains "$TRACE_FILE" "brew " "storage-plan shorthand does not invoke brew"
}

test_help_completion_and_version_metadata_parity() {
    setup_env metadata-parity
    local out="${TEST_ROOT}/metadata-parity.out"

    run_freshen "$out" --help --no-color
    assert_status 0 $? "metadata parity help exits cleanly"
    local flag
    for flag in --dry-run --clean-only --formula-only --cask-only --no-greedy --no-cleanup --no-cache --storage-plan --dev-prune --no-mas --doctor --sequential --progress --replace --no-sudo-preflight --verbose --quiet --no-color --version --help; do
        assert_contains "$FRESHEN_FILE" "$flag" "completion/source mentions ${flag}"
        assert_contains "$out" "$flag" "help mentions ${flag}"
    done
    assert_contains "$FRESHEN_FILE" "freshen v1.11.0" "header version matches release"
    assert_not_contains "$FRESHEN_FILE" "_arguments -s" "completion does not advertise unsupported stacked short options"
    assert_contains "$FRESHEN_FILE" ">/dev/null 2>&1 &!" "notification subprocess is disowned to avoid job-control noise"
    assert_contains "$out" "FRESHEN_LOW_POWER" "help documents low-power mode"
    run_freshen "$out" --version --no-color
    assert_contains "$out" "freshen 1.11.0 (2026-08-27)" "version output matches release metadata"
}

test_batch_formula_partial_failure() {
    setup_env batch-formula
    export BREW_OUTDATED_FORMULAE=$'alpha\nbeta'
    export BREW_FORMULA_UPGRADE_RC=1
    export BREW_FORMULA_UPGRADE_OUTPUT=$'==> Upgrading alpha\nalpha 1.0 -> 1.1\nError: beta failed'
    local out="${TEST_ROOT}/batch-formula.out"

    run_freshen "$out" --yes --no-mas --no-cleanup --no-cache --no-color
    assert_status 1 $? "batch formula partial failure returns non-zero"
    assert_contains "$out" "Formulae: degraded — attempted 2, confirmed 1, failed 1" "formula phase reports exact partial failure counts"
}

test_batch_cask_partial_failure() {
    setup_env batch-cask
    export BREW_OUTDATED_CASKS=$'firefox\nraycast'
    export BREW_CASK_UPGRADE_RC=1
    export BREW_CASK_UPGRADE_OUTPUT=$'==> Upgrading Cask firefox\nfirefox: 1.0 -> 1.1\nError: raycast failed'
    local out="${TEST_ROOT}/batch-cask.out"

    run_freshen "$out" --yes --formula-only --no-mas --no-cleanup --no-cache --no-color
    assert_status 0 $? "formula-only skips casks cleanly"
    assert_contains "$out" "Casks: skipped — disabled by --formula-only" "formula-only skips cask lane"

    export BREW_OUTDATED_FORMULAE=''
    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --no-color
    assert_status 1 $? "cask-only partial failure returns non-zero"
    assert_contains "$out" "Casks: degraded — attempted 2, confirmed 1, failed 1" "cask phase reports exact partial failure counts"
}

test_batch_cask_all_confirmed_with_brew_caveats_is_done() {
    setup_env batch-cask-caveats
    export BREW_OUTDATED_CASKS=$'firefox\nraycast'
    export BREW_CASK_UPGRADE_RC=1
    export BREW_CASK_UPGRADE_OUTPUT=$'==> Upgrading Cask firefox\nfirefox: 1.0 -> 1.1\n==> Upgrading Cask raycast\nraycast: 1.0 -> 1.1\nError: Problems with multiple casks:\nfirefox: It seems the App source is not there.\nraycast: It seems the App source is not there.\n==> Upgraded 2 outdated packages\nfirefox 1.0 -> 1.1\nraycast 1.0 -> 1.1'
    local out="${TEST_ROOT}/batch-cask-caveats.out"

    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --progress=plain --no-color
    assert_status 0 $? "all-confirmed cask caveats do not fail the run"
    assert_contains "$out" "Casks: done — attempted 2, confirmed 2, caveats in log" "all-confirmed cask caveats are reported as done with log caveat"
    assert_not_contains "$out" "Casks: degraded" "all-confirmed cask caveats are not degraded"
}

test_cask_sudo_preflight_happens_before_upgrade() {
    setup_env cask-sudo
    export BREW_OUTDATED_CASKS='firefox'
    export BREW_CASK_SINGLE_OUTPUT_FIREFOX=$'==> Upgrading Cask firefox\nfirefox: 1.0 -> 1.1'
    local out="${TEST_ROOT}/cask-sudo.out"

    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --progress=plain --no-color
    assert_status 0 $? "cask-only upgrade exits cleanly after sudo preflight"
    assert_contains "$TRACE_FILE" "sudo -v" "cask lane validates sudo before upgrade"

    local sudo_line upgrade_line
    sudo_line=$(grep -nF "sudo -v" "$TRACE_FILE" | sed -n '1s/:.*//p')
    upgrade_line=$(grep -nF "brew upgrade --cask" "$TRACE_FILE" | sed -n '1s/:.*//p')
    if [[ -n "$sudo_line" && -n "$upgrade_line" && "$sudo_line" -lt "$upgrade_line" ]]; then
        pass "sudo preflight precedes brew cask upgrade"
    else
        print -u2 -r -- "--- trace ---"
        sed -n '1,120p' "$TRACE_FILE" >&2
        fail "sudo preflight precedes brew cask upgrade"
    fi
}

test_sudo_preflight_failure_skips_casks() {
    setup_env cask-sudo-fail
    export BREW_OUTDATED_CASKS='firefox'
    export SUDO_RC=1
    local out="${TEST_ROOT}/cask-sudo-fail.out"

    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --progress=plain --no-color
    assert_status 1 $? "sudo preflight failure exits non-zero"
    assert_contains "$out" "sudo preflight failed; skipped 1 casks" "sudo preflight failure reports skipped casks"
    assert_contains "$TRACE_FILE" "sudo -v" "sudo preflight failure validates sudo"
    assert_not_contains "$TRACE_FILE" "brew upgrade --cask" "sudo preflight failure skips cask upgrade"
}

test_no_sudo_preflight_skips_validation() {
    setup_env cask-no-sudo-preflight
    export BREW_OUTDATED_CASKS='firefox'
    export BREW_CASK_SINGLE_OUTPUT_FIREFOX=$'==> Upgrading Cask firefox\nfirefox: 1.0 -> 1.1'
    local out="${TEST_ROOT}/cask-no-sudo-preflight.out"

    run_freshen "$out" --yes --cask-only --no-sudo-preflight --no-mas --no-cleanup --no-cache --progress=plain --no-color
    assert_status 0 $? "no-sudo-preflight cask upgrade exits cleanly"
    assert_not_contains "$TRACE_FILE" "sudo -v" "no-sudo-preflight skips sudo validation"
    assert_contains "$TRACE_FILE" "brew upgrade --cask" "no-sudo-preflight still runs cask upgrade"
}

test_mas_warning_rows_are_not_counted_as_apps() {
    setup_env mas-warnings
    export MAS_OUTDATED=$'==> Indexing applications\nWarning: index is stale\n1234 OneApp\n5678 AnotherApp (2.0)'
    local out="${TEST_ROOT}/mas-warnings.out"

    run_freshen "$out" --dry-run --yes --progress=plain --no-color
    assert_status 0 $? "mas warning inventory dry-run exits cleanly"
    assert_contains "$out" "App Store: 2" "only numeric mas app rows count as outdated apps"
    assert_not_contains "$out" "Indexing applications" "mas warnings are not shown as app names"
    assert_not_contains "$out" "Warning: index is stale" "mas warnings are kept out of inventory display"
}

test_progress_plain_has_no_cursor_controls() {
    setup_env progress-plain
    export BREW_OUTDATED_FORMULAE='alpha'
    local out="${TEST_ROOT}/progress-plain.out"

    run_freshen "$out" --dry-run --yes --progress=plain --no-mas --no-color
    assert_status 0 $? "plain progress dry-run exits cleanly"
    assert_not_contains "$out" $'\e[' "plain no-color output has no ANSI escapes"
    assert_not_contains "$out" $'\e[?25l' "plain progress does not hide cursor"
    assert_not_contains "$out" $'\e[2K' "plain progress does not clear lines"
}

test_append_progress_shows_meter_and_log_path() {
    setup_env progress-meter
    export BREW_OUTDATED_FORMULAE=$'alpha\nbeta'
    export BREW_FORMULA_UPGRADE_OUTPUT=$'==> Upgrading alpha\nalpha 1.0 -> 1.1\n==> Upgrading beta\nbeta 1.0 -> 1.1'
    local out="${TEST_ROOT}/progress-meter.out"

    run_freshen "$out" --yes --no-mas --no-cleanup --no-cache --progress=plain --no-color
    assert_status 0 $? "append progress meter run exits cleanly"
    assert_contains "$out" "Log:" "append-only progress shows the log path without verbose mode"
    assert_contains "$out" "Progress: [" "append-only progress shows a progress meter"
    assert_contains "$out" "0/2" "append-only progress shows starting count"
    assert_contains "$out" "2/2" "append-only progress shows completed count"
    assert_contains "$out" "Formulae: done — attempted 2, confirmed 2" "append progress keeps phase summary readable"
    assert_not_contains "$out" $'\e[' "plain progress meter output has no ANSI escapes"
}

test_invalid_progress_mode_fails() {
    setup_env invalid-progress
    local out="${TEST_ROOT}/invalid-progress.out"

    run_freshen "$out" --progress=sparkles --no-color
    assert_status 2 $? "invalid progress mode exits with usage error"
    assert_contains "$out" "--progress must be one of auto, live, lines, plain" "invalid progress mode explains valid values"
}

test_mas_outdated_timeout_degrades_inventory_and_summary() {
    setup_env mas-outdated-timeout
    export FRESHEN_MAS_TIMEOUT_SEC=1
    export MAS_OUTDATED_SLEEP=3
    local out="${TEST_ROOT}/mas-outdated-timeout.out"

    run_freshen "$out" --dry-run --yes --progress=plain --no-color
    assert_status 1 $? "mas outdated timeout dry-run exits degraded"
    assert_contains "$out" "Inventory: degraded" "mas outdated timeout degrades inventory"
    assert_contains "$out" "apps 0" "mas outdated timeout inventory reports zero apps"
}

test_password_like_output_is_redacted() {
    setup_env redaction
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_FORMULA_SINGLE_OUTPUT_ALPHA=$'Password: please enter secret\n==> Upgrading alpha\nalpha 1.0 -> 1.1'
    local out="${TEST_ROOT}/redaction.out"

    run_freshen "$out" --yes --sequential --no-mas --no-cleanup --no-cache --verbose --no-color
    assert_status 0 $? "password-like output run exits cleanly"
    assert_contains "$out" "[redacted credential prompt]" "password-like terminal output is redacted"
    assert_not_contains "$out" "Password: please enter secret" "password-like terminal output is not leaked"

    local log_path
    log_path="$(find_log_path "$out")"
    if [[ -n "$log_path" && -f "$log_path" ]]; then
        assert_contains "$log_path" "[redacted credential prompt]" "password-like log output is redacted"
        assert_not_contains "$log_path" "Password: please enter secret" "password-like log output is not leaked"
    else
        fail "redaction test emits a usable log path"
    fi
}

test_sensitive_output_patterns_are_redacted() {
    setup_env sensitive-redaction
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_FORMULA_SINGLE_OUTPUT_ALPHA=$'Authorization: Bearer abc123\napi_key=secret-value\n==> Upgrading alpha\nalpha 1.0 -> 1.1'
    local out="${TEST_ROOT}/sensitive-redaction.out"

    run_freshen "$out" --yes --sequential --no-mas --no-cleanup --no-cache --verbose --no-color
    assert_status 0 $? "sensitive output run exits cleanly"
    assert_contains "$out" "[redacted sensitive output]" "sensitive terminal output is redacted"
    assert_not_contains "$out" "Bearer abc123" "bearer token is not leaked to terminal"
    assert_not_contains "$out" "api_key=secret-value" "api key is not leaked to terminal"

    local log_path
    log_path="$(find_log_path "$out")"
    if [[ -n "$log_path" && -f "$log_path" ]]; then
        assert_contains "$log_path" "[redacted sensitive output]" "sensitive log output is redacted"
        assert_not_contains "$log_path" "Bearer abc123" "bearer token is not leaked to log"
        assert_not_contains "$log_path" "api_key=secret-value" "api key is not leaked to log"
    else
        fail "sensitive redaction test emits a usable log path"
    fi
}

test_hyphenated_api_key_output_is_redacted() {
    setup_env hyphen-api-key-redaction
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_FORMULA_SINGLE_OUTPUT_ALPHA=$'X-API-Key: abc123\n==> Upgrading alpha\nalpha 1.0 -> 1.1'
    local out="${TEST_ROOT}/hyphen-api-key-redaction.out"

    run_freshen "$out" --yes --sequential --no-mas --no-cleanup --no-cache --verbose --no-color
    assert_status 0 $? "hyphenated api key output run exits cleanly"
    assert_contains "$out" "[redacted sensitive output]" "hyphenated api key terminal output is redacted"
    assert_not_contains "$out" "X-API-Key: abc123" "hyphenated api key is not leaked to terminal"
}

test_invalid_environment_values_warn_and_fallback() {
    setup_env invalid-env
    export FRESHEN_CACHE_TIMEOUT_SEC=not-a-number
    export FRESHEN_RENDER_INTERVAL_MS=-20
    local out="${TEST_ROOT}/invalid-env.out"

    run_freshen "$out" --clean-only --yes --no-cleanup --progress=plain --no-color
    assert_status 0 $? "invalid env values fall back without failing"
    assert_contains "$out" "FRESHEN_CACHE_TIMEOUT_SEC must be a positive integer; using 120" "invalid cache timeout warning is actionable"
    assert_contains "$out" "FRESHEN_RENDER_INTERVAL_MS must be a positive integer; using 500" "invalid render interval warning is actionable"
    assert_contains "$TRACE_FILE" "npm cache clean --force" "fallback cache timeout still allows cache cleanup"
}

test_bun_cache_path_safety_refuses_dangerous_paths() {
    setup_env bun-cache-safety
    mkdir -p "${TEST_HOME}/.bun/install/cache"
    export BUN_INSTALL_CACHE_DIR="/"
    local out="${TEST_ROOT}/bun-cache-safety.out"

    run_freshen "$out" --clean-only --yes --no-cleanup --progress=plain --no-color
    assert_status 1 $? "dangerous bun cache path degrades run"
    assert_contains "$out" "bun: refusing unsafe cache path /" "dangerous bun cache path is reported"
    assert_not_contains "$TRACE_FILE" "command rm -rf -- /" "dangerous bun cache path is never removed"
}

test_bun_cache_path_rejects_command_delimiter_injection() {
    setup_env bun-cache-delimiter
    local safe_dir="${TEST_HOME}/safe-bun-cache"
    local victim_dir="${TEST_ROOT}/victim-dir"
    mkdir -p "$safe_dir" "$victim_dir"
    export BUN_INSTALL_CACHE_DIR="${safe_dir}|${victim_dir}"
    local out="${TEST_ROOT}/bun-cache-delimiter.out"

    run_freshen "$out" --clean-only --yes --no-cleanup --progress=plain --no-color
    assert_status 1 $? "bun cache delimiter injection degrades run"
    assert_contains "$out" "bun: refusing unsafe cache path ${safe_dir}|${victim_dir}" "bun delimiter path is reported as unsafe"
    if [[ -d "$victim_dir" ]]; then
        pass "bun delimiter injection does not delete extra path"
    else
        fail "bun delimiter injection does not delete extra path"
    fi
}

test_bun_cache_path_rejects_symlink_escape() {
    setup_env bun-cache-symlink
    local outside_root="${TEST_ROOT}/outside-root"
    local escaped_cache="${outside_root}/escaped-cache"
    local link_path="${TEST_HOME}/cache-link"
    mkdir -p "$escaped_cache"
    ln -s "$outside_root" "$link_path"
    export BUN_INSTALL_CACHE_DIR="${link_path}/escaped-cache"
    local out="${TEST_ROOT}/bun-cache-symlink.out"

    run_freshen "$out" --clean-only --yes --no-cleanup --progress=plain --no-color
    assert_status 1 $? "bun cache symlink escape degrades run"
    assert_contains "$out" "bun: refusing unsafe cache path ${link_path}/escaped-cache" "bun symlink escape path is reported as unsafe"
    if [[ -d "$escaped_cache" ]]; then
        pass "bun symlink escape does not delete outside cache"
    else
        fail "bun symlink escape does not delete outside cache"
    fi
}

test_bun_cache_path_rejects_arbitrary_home_directory() {
    setup_env bun-cache-arbitrary-home
    local documents_dir="${TEST_HOME}/Documents"
    mkdir -p "$documents_dir"
    export BUN_INSTALL_CACHE_DIR="$documents_dir"
    local out="${TEST_ROOT}/bun-cache-arbitrary-home.out"

    run_freshen "$out" --clean-only --yes --no-cleanup --progress=plain --no-color
    assert_status 1 $? "bun arbitrary home directory degrades run"
    assert_contains "$out" "bun: refusing unsafe cache path ${documents_dir}" "bun arbitrary home directory is reported as unsafe"
    if [[ -d "$documents_dir" ]]; then
        pass "bun arbitrary home directory is not deleted"
    else
        fail "bun arbitrary home directory is not deleted"
    fi
}

test_dev_prune_dry_run_and_gomi_safety() {
    setup_env dev-prune
    local project_root="${TEST_ROOT}/project with space"
    local modules_dir="${project_root}/node_modules"
    mkdir -p "$modules_dir"
    freshen_stamp_mtime_days_ago "$modules_dir" 20
    local out="${TEST_ROOT}/dev-prune.out"

    run_freshen "$out" --clean-only --dry-run --dev-prune --dev-prune-root="$project_root" --progress=plain --no-color
    assert_status 0 $? "dev-prune dry-run exits cleanly without gomi"
    assert_contains "$out" "Dev Prune" "dev-prune dry-run prints candidate plan"
    assert_not_contains "$TRACE_FILE" "gomi --" "dev-prune dry-run does not trash candidates"

    : >| "$TRACE_FILE"
    run_freshen "$out" --clean-only --yes --no-cleanup --dev-prune --dev-prune-root="$project_root" --progress=plain --no-color
    assert_status 1 $? "dev-prune execution without gomi degrades"
    assert_contains "$out" "dev-prune: gomi is required; refusing to use rm fallback" "dev-prune missing gomi refuses rm fallback"
    assert_not_contains "$TRACE_FILE" "rm -rf" "dev-prune missing gomi never uses rm fallback"

    : >| "$TRACE_FILE"
    write_gomi_stub
    run_freshen "$out" --clean-only --yes --no-cleanup --dev-prune --dev-prune-root="$project_root" --progress=plain --no-color
    assert_status 0 $? "dev-prune execution with gomi exits cleanly"
    assert_contains "$TRACE_FILE" "gomi -- ${modules_dir}" "dev-prune passes candidate path to gomi with separator"
}

test_dev_prune_refuses_broad_roots() {
    setup_env dev-prune-broad-root
    write_gomi_stub
    mkdir -p "${TEST_HOME}/project/node_modules"
    local out="${TEST_ROOT}/dev-prune-broad-root.out"

    run_freshen "$out" --clean-only --dry-run --dev-prune --dev-prune-root="$TEST_HOME" --progress=plain --no-color
    assert_status 1 $? "dev-prune broad home root dry-run exits degraded"
    assert_contains "$out" "--dev-prune root is too broad: ${TEST_HOME}" "dev-prune broad home root dry-run reports refusal"

    : >| "$TRACE_FILE"
    run_freshen "$out" --clean-only --yes --no-cleanup --dev-prune --dev-prune-root="$TEST_HOME" --progress=plain --no-color
    assert_status 1 $? "dev-prune broad home root degrades run"
    assert_contains "$out" "dev-prune: refusing broad root ${TEST_HOME}" "dev-prune broad home root is reported"
    assert_not_contains "$TRACE_FILE" "gomi --" "dev-prune broad home root does not call gomi"

    : >| "$TRACE_FILE"
    export FRESHEN_DEV_PRUNE_MAX_SCAN=1
    run_freshen "$out" --clean-only --dry-run --dev-prune --dev-prune-root=/tmp --progress=plain --no-color
    assert_status 1 $? "dev-prune top-level tmp root dry-run exits degraded"
    assert_contains "$out" "--dev-prune root is too broad: /tmp" "dev-prune top-level tmp root reports refusal"
}

test_low_power_mode_forces_plain_and_disables_notification_noise() {
    setup_env low-power
    export FRESHEN_LOW_POWER=1
    export BREW_OUTDATED_FORMULAE='alpha'
    local out="${TEST_ROOT}/low-power.out"

    run_freshen "$out" --dry-run --yes --progress=live --no-mas --no-color
    assert_status 0 $? "low-power dry-run exits cleanly"
    assert_not_contains "$out" $'\e[?25l' "low-power mode does not hide cursor even when live requested"
    assert_not_contains "$out" $'\a' "low-power mode does not emit terminal bell"
}

test_log_files_are_unique_and_private() {
    setup_env log-private
    local out1="${TEST_ROOT}/log-private-1.out"
    local out2="${TEST_ROOT}/log-private-2.out"

    run_freshen "$out1" --dry-run --yes --verbose --no-mas --no-color
    assert_status 0 $? "first verbose dry-run exits cleanly"
    run_freshen "$out2" --dry-run --yes --verbose --no-mas --no-color
    assert_status 0 $? "second verbose dry-run exits cleanly"

    local log1 log2 perms
    log1="$(find_log_path "$out1")"
    log2="$(find_log_path "$out2")"
    if [[ -n "$log1" && -n "$log2" && -f "$log1" && -f "$log2" && "$log1" != "$log2" ]]; then
        pass "same-second logs use unique paths"
    else
        print -u2 -r -- "log1=${log1} log2=${log2}"
        fail "same-second logs use unique paths"
    fi
    perms="$(perl -e 'printf "%03o", ((stat($ARGV[0]))[2] & 0777)' "$log1")"
    if [[ "$perms" == "600" ]]; then
        pass "freshen logs are private"
    else
        print -u2 -r -- "expected log perms 600, got ${perms}"
        fail "freshen logs are private"
    fi
}

test_log_directory_with_spaces_is_preserved() {
    setup_env log-space
    TEST_STATE="${TEST_ROOT}/state with space"
    mkdir -p "$TEST_STATE"
    local out="${TEST_ROOT}/log-space.out"

    run_freshen "$out" --dry-run --yes --verbose --no-mas --no-color
    assert_status 0 $? "verbose dry-run with spaced state dir exits cleanly"
    local log_path
    log_path="$(find_log_path "$out")"
    if [[ "$log_path" == *"state with space"* && -f "$log_path" ]]; then
        pass "log path preserves spaces in state directory"
    else
        print -u2 -r -- "log_path=${log_path}"
        fail "log path preserves spaces in state directory"
    fi
}

test_mas_warning_rows_are_redacted_in_logs() {
    setup_env mas-warning-redaction
    export MAS_OUTDATED=$'Warning: Authorization Bearer abc123\n1234 OneApp'
    local out="${TEST_ROOT}/mas-warning-redaction.out"

    run_freshen "$out" --dry-run --yes --verbose --no-color
    assert_status 0 $? "mas warning redaction dry-run exits cleanly"
    local log_path
    log_path="$(find_log_path "$out")"
    if [[ -n "$log_path" && -f "$log_path" ]]; then
        assert_contains "$log_path" "[mas outdated] [redacted sensitive output]" "mas warning row is redacted in log"
        assert_not_contains "$log_path" "Bearer abc123" "mas warning token is not leaked to log"
    else
        fail "mas warning redaction emits a usable log path"
    fi
}

test_invalid_uv_timeout_override_warns_and_fallbacks() {
    setup_env invalid-uv-timeout
    export FRESHEN_UV_CACHE_TIMEOUT_SEC=bad-value
    local out="${TEST_ROOT}/invalid-uv-timeout.out"

    run_freshen "$out" --clean-only --yes --no-cleanup --progress=plain --no-color
    assert_status 0 $? "invalid uv timeout override falls back without failing"
    assert_contains "$out" "FRESHEN_UV_CACHE_TIMEOUT_SEC must be a positive integer; using 300" "invalid uv timeout warning is actionable"
    assert_contains "$TRACE_FILE" "uv cache clean" "uv cache cleanup still runs with fallback timeout"
}

test_cache_mixed_results() {
    setup_env caches
    export FRESHEN_CACHE_TIMEOUT_SEC=1
    export FRESHEN_UV_CACHE_TIMEOUT_SEC=1
    export STUB_SLEEP_UV=3
    export STUB_RC_GEM=1
    export STUB_STDERR_GEM='gem cleanup error'
    local out="${TEST_ROOT}/cache.out"
    mkdir -p "${TEST_HOME}/.bun/install/cache"

    run_freshen "$out" --yes --no-mas --no-cleanup --gem-cleanup --no-color
    assert_status 1 $? "cache failures bubble up"
    assert_contains "$out" "Caches: degraded — attempted 9, cleaned 7, failed 2" "cache phase reports mixed success and timeout exactly"
    assert_contains "$out" "failed: uv, gem" "cache phase names failed cache targets"
    assert_contains "$out" "Attention" "degraded runs include an attention section"
    assert_contains "$out" "Caches: attempted 9, cleaned 7, failed 2, failed: uv, gem" "attention section repeats actionable cache failure details"
    assert_contains "$out" "uv: cache cleanup failed (timed out)" "cache timeout is labeled explicitly"
    assert_contains "$out" "gem: cache cleanup failed" "non-timeout cache failure is labeled"
}

test_mas_failure_logs_stderr() {
    setup_env mas-fail
    export MAS_OUTDATED='9876 FancyApp'
    export MAS_UPDATE_RC=2
    export MAS_UPDATE_STDERR='mas exploded'
    local out="${TEST_ROOT}/mas.out"

    run_freshen "$out" --yes --no-cache --no-cleanup --no-color
    assert_status 1 $? "mas failure returns non-zero"
    assert_contains "$out" "App Store: degraded — attempted 1, failed 1" "App Store phase degrades explicitly"

    local log_path
    log_path="$(find_log_path "$out")"
    if [[ -n "$log_path" && -f "$log_path" ]]; then
        assert_contains "$log_path" "mas exploded" "mas stderr lands in the log"
    else
        fail "mas failure emits a usable log path"
    fi
}

test_mas_update_runs_without_account_preflight() {
    setup_env mas-no-account-preflight
    export MAS_OUTDATED=$'9876 FancyApp\n5432 BlockedApp'
    export MAS_UPDATE_RC=2
    export MAS_UPDATE_STDERR='This Apple Account has been disabled.'
    local out="${TEST_ROOT}/mas-no-account-preflight.out"

    run_freshen "$out" --yes --no-cache --no-cleanup --no-color
    assert_status 1 $? "mas update failure returns non-zero"
    assert_not_contains "$TRACE_FILE" "mas account" "mas update does not use unsupported account preflight"
    assert_contains "$TRACE_FILE" "mas update" "mas update is attempted directly"
    assert_contains "$out" "App Store: degraded — attempted 2, failed 2" "App Store phase reports failed update batch"
}

test_interrupt_reporting() {
    setup_env interrupt
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_FORMULA_SINGLE_SLEEP_ALPHA=10
    local out="${TEST_ROOT}/interrupt.out"
    local rc=0

    PATH="${TEST_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="${TEST_HOME}" \
    XDG_STATE_HOME="${TEST_STATE}" \
    TMPDIR="${TEST_TMP}" \
    TRACE_FILE="${TRACE_FILE}" \
    FRESHEN_UNDER_TEST="${FRESHEN_UNDER_TEST:-$FRESHEN_FILE}" \
    zsh -fc 'fpath=("$1" $fpath); autoload -Uz freshen; shift; freshen "$@"' zsh "$FRESHEN_DIR" --yes --no-mas --no-cleanup --no-cache --no-color >"$out" 2>&1 &
    local runner_pid=$!
    local tries=0
    while (( tries < 50 )) && ! grep -Fq -- "brew upgrade alpha" "$TRACE_FILE"; do
        sleep 0.1
        (( tries++ ))
    done
    kill -INT "$runner_pid"
    wait "$runner_pid" || rc=$?

    assert_interrupt_status "$rc" "interrupt returns 130 or 143"
    assert_contains "$out" "Interrupted — completed 0, remaining 1, active phase formulae" "interrupt summary reports progress and active phase"
}

test_interrupt_stops_mas_inventory_child() {
    setup_env interrupt-mas
    export MAS_OUTDATED_SLEEP=10
    export FRESHEN_MAS_TIMEOUT_SEC=20
    export MAS_PID_FILE="${TEST_ROOT}/mas.pid"
    local out="${TEST_ROOT}/interrupt-mas.out"
    local rc=0

    PATH="${TEST_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="${TEST_HOME}" \
    XDG_STATE_HOME="${TEST_STATE}" \
    TMPDIR="${TEST_TMP}" \
    TRACE_FILE="${TRACE_FILE}" \
    MAS_PID_FILE="${MAS_PID_FILE}" \
    MAS_OUTDATED_SLEEP="${MAS_OUTDATED_SLEEP}" \
    FRESHEN_MAS_TIMEOUT_SEC="${FRESHEN_MAS_TIMEOUT_SEC}" \
    FRESHEN_UNDER_TEST="${FRESHEN_UNDER_TEST:-$FRESHEN_FILE}" \
    zsh -fc 'fpath=("$1" $fpath); autoload -Uz freshen; shift; freshen "$@"' zsh "$FRESHEN_DIR" --yes --no-cache --no-cleanup --no-color >"$out" 2>&1 &
    local runner_pid=$!
    local tries=0
    while (( tries < 50 )) && [[ ! -s "$MAS_PID_FILE" ]]; do
        sleep 0.1
        (( tries++ ))
    done
    if [[ ! -s "$MAS_PID_FILE" ]]; then
        kill -TERM "$runner_pid" 2>/dev/null || true
        wait "$runner_pid" 2>/dev/null || true
        fail "mas inventory child pid is observed before interrupt"
        return
    fi
    local mas_pid="$(< "$MAS_PID_FILE")"
    if ! kill -0 "$mas_pid" 2>/dev/null; then
        kill -TERM "$runner_pid" 2>/dev/null || true
        wait "$runner_pid" 2>/dev/null || true
        fail "mas inventory child is running before interrupt"
        return
    fi
    kill -INT "$runner_pid"
    wait "$runner_pid" || rc=$?
    sleep 0.3

    assert_interrupt_status "$rc" "mas inventory interrupt returns 130 or 143"
    if [[ -n "$mas_pid" ]] && kill -0 "$mas_pid" 2>/dev/null; then
        kill -TERM "$mas_pid" 2>/dev/null || true
        fail "mas inventory child is stopped on interrupt"
    else
        pass "mas inventory child is stopped on interrupt"
    fi
}

test_autoload_resolution() {
    setup_env autoload
    local out="${TEST_ROOT}/autoload.out"
    zsh -fc 'fpath=("$1" $fpath); autoload -Uz freshen; whence -v freshen' zsh "$FRESHEN_DIR" >"$out" 2>&1
    assert_contains "$out" "freshen is an autoload shell function" "autoload resolution still works"
}

test_interrupt_stops_parallel_brew_outdated_children() {
    setup_env interrupt-brew-outdated
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_OUTDATED_CASKS='beta'
    export BREW_OUTDATED_FORMULAE_SLEEP=10
    export BREW_OUTDATED_CASKS_SLEEP=10
    export BREW_FORMULAE_OUTDATED_PID_FILE="${TEST_ROOT}/brew-formulae.pid"
    export BREW_CASK_OUTDATED_PID_FILE="${TEST_ROOT}/brew-cask.pid"
    local out="${TEST_ROOT}/interrupt-brew-outdated.out"
    local rc=0

    PATH="${TEST_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="${TEST_HOME}" \
    XDG_STATE_HOME="${TEST_STATE}" \
    TMPDIR="${TEST_TMP}" \
    TRACE_FILE="${TRACE_FILE}" \
    BREW_FORMULAE_OUTDATED_PID_FILE="${BREW_FORMULAE_OUTDATED_PID_FILE}" \
    BREW_CASK_OUTDATED_PID_FILE="${BREW_CASK_OUTDATED_PID_FILE}" \
    BREW_OUTDATED_FORMULAE_SLEEP="${BREW_OUTDATED_FORMULAE_SLEEP}" \
    BREW_OUTDATED_CASKS_SLEEP="${BREW_OUTDATED_CASKS_SLEEP}" \
    FRESHEN_UNDER_TEST="${FRESHEN_UNDER_TEST:-$FRESHEN_FILE}" \
    zsh -fc 'fpath=("$1" $fpath); autoload -Uz freshen; shift; freshen "$@"' zsh "$FRESHEN_DIR" --dry-run --yes --no-cache --no-cleanup --no-color >"$out" 2>&1 &
    local runner_pid=$!
    local tries=0
    while (( tries < 50 )) && [[ ! -s "$BREW_FORMULAE_OUTDATED_PID_FILE" || ! -s "$BREW_CASK_OUTDATED_PID_FILE" ]]; do
        sleep 0.1
        (( tries++ ))
    done
    if [[ ! -s "$BREW_FORMULAE_OUTDATED_PID_FILE" || ! -s "$BREW_CASK_OUTDATED_PID_FILE" ]]; then
        kill -TERM "$runner_pid" 2>/dev/null || true
        wait "$runner_pid" 2>/dev/null || true
        fail "parallel brew outdated children start before interrupt"
        return
    fi
    local formulae_pid="$(< "$BREW_FORMULAE_OUTDATED_PID_FILE")"
    local cask_pid="$(< "$BREW_CASK_OUTDATED_PID_FILE")"
    kill -INT "$runner_pid"
    wait "$runner_pid" || rc=$?
    sleep 0.3

    assert_interrupt_status "$rc" "brew outdated inventory interrupt returns 130 or 143"
    if [[ -n "$formulae_pid" ]] && kill -0 "$formulae_pid" 2>/dev/null; then
        kill -TERM "$formulae_pid" 2>/dev/null || true
        fail "formulae brew outdated child is stopped on interrupt"
    else
        pass "formulae brew outdated child is stopped on interrupt"
    fi
    if [[ -n "$cask_pid" ]] && kill -0 "$cask_pid" 2>/dev/null; then
        kill -TERM "$cask_pid" 2>/dev/null || true
        fail "cask brew outdated child is stopped on interrupt"
    else
        pass "cask brew outdated child is stopped on interrupt"
    fi
}

test_dev_prune_rejects_symlink_at_execution() {
    setup_env dev-prune-symlink
    write_gomi_stub
    local project_root="${TEST_ROOT}/project"
    local modules_dir="${project_root}/node_modules"
    local outside_dir="${TEST_ROOT}/outside-target"
    mkdir -p "$project_root" "$outside_dir"
    ln -s "$outside_dir" "$modules_dir"
    freshen_stamp_mtime_days_ago "$modules_dir" 20
    local out="${TEST_ROOT}/dev-prune-symlink.out"

    run_freshen "$out" --clean-only --yes --no-cleanup --dev-prune --dev-prune-root="$project_root" --progress=plain --no-color
    assert_status 1 $? "dev-prune symlink target degrades run"
    assert_contains "$out" "dev-prune: refusing unsafe target ${modules_dir}" "dev-prune symlink target is refused at execution"
    assert_not_contains "$TRACE_FILE" "gomi -- ${modules_dir}" "dev-prune symlink target is not passed to gomi"
}

test_help_and_version
test_capital_shorthands
test_clean_only_dry_run_skips_inventory
test_clean_only_executes_cleanup_and_caches_without_inventory
test_clean_only_cache_only_does_not_require_brew
test_noninteractive_requires_yes
test_quiet_does_not_imply_yes
test_dry_run_is_inventory_only
test_storage_plan_is_read_only_without_brew
test_invalid_restore_target_warns_without_mutation
test_no_greedy_shorthand_cask_invocation
test_batch_unknown_classification_degrades
test_cleanup_degraded_paths
test_doctor_lane_success_and_failure
test_default_run_requires_brew_but_storage_plan_does_not
test_help_completion_and_version_metadata_parity
test_batch_formula_partial_failure
test_batch_cask_partial_failure
test_batch_cask_all_confirmed_with_brew_caveats_is_done
test_cask_sudo_preflight_happens_before_upgrade
test_sudo_preflight_failure_skips_casks
test_no_sudo_preflight_skips_validation
test_mas_warning_rows_are_not_counted_as_apps
test_progress_plain_has_no_cursor_controls
test_append_progress_shows_meter_and_log_path
test_invalid_progress_mode_fails
test_mas_outdated_timeout_degrades_inventory_and_summary
test_password_like_output_is_redacted
test_sensitive_output_patterns_are_redacted
test_hyphenated_api_key_output_is_redacted
test_invalid_environment_values_warn_and_fallback
test_bun_cache_path_safety_refuses_dangerous_paths
test_bun_cache_path_rejects_command_delimiter_injection
test_bun_cache_path_rejects_symlink_escape
test_bun_cache_path_rejects_arbitrary_home_directory
test_dev_prune_dry_run_and_gomi_safety
test_dev_prune_refuses_broad_roots
test_low_power_mode_forces_plain_and_disables_notification_noise
test_log_files_are_unique_and_private
test_log_directory_with_spaces_is_preserved
test_mas_warning_rows_are_redacted_in_logs
test_invalid_uv_timeout_override_warns_and_fallbacks
test_cache_mixed_results
test_mas_failure_logs_stderr
test_mas_update_runs_without_account_preflight
test_interrupt_reporting
test_interrupt_stops_mas_inventory_child
test_interrupt_stops_parallel_brew_outdated_children
test_dev_prune_rejects_symlink_at_execution
test_autoload_resolution

# Optional case packs (parallel-owned RED/GREEN modules)
local _freshen_case_file
for _freshen_case_file in "${TEST_SCRIPT_DIR}"/cases/*.zsh(N); do
    source "$_freshen_case_file"
done

# Auto-run any test_* defined by cases that were not already invoked above
local _freshen_test_name
local -a _freshen_invoked_tests=(
    test_help_and_version
    test_capital_shorthands
    test_clean_only_dry_run_skips_inventory
    test_clean_only_executes_cleanup_and_caches_without_inventory
    test_clean_only_cache_only_does_not_require_brew
    test_noninteractive_requires_yes
    test_quiet_does_not_imply_yes
    test_dry_run_is_inventory_only
    test_storage_plan_is_read_only_without_brew
    test_invalid_restore_target_warns_without_mutation
    test_no_greedy_shorthand_cask_invocation
    test_batch_unknown_classification_degrades
    test_cleanup_degraded_paths
    test_doctor_lane_success_and_failure
    test_default_run_requires_brew_but_storage_plan_does_not
    test_help_completion_and_version_metadata_parity
    test_batch_formula_partial_failure
    test_batch_cask_partial_failure
    test_batch_cask_all_confirmed_with_brew_caveats_is_done
    test_cask_sudo_preflight_happens_before_upgrade
    test_sudo_preflight_failure_skips_casks
    test_no_sudo_preflight_skips_validation
    test_mas_warning_rows_are_not_counted_as_apps
    test_progress_plain_has_no_cursor_controls
    test_append_progress_shows_meter_and_log_path
    test_invalid_progress_mode_fails
    test_mas_outdated_timeout_degrades_inventory_and_summary
    test_password_like_output_is_redacted
    test_sensitive_output_patterns_are_redacted
    test_hyphenated_api_key_output_is_redacted
    test_invalid_environment_values_warn_and_fallback
    test_bun_cache_path_safety_refuses_dangerous_paths
    test_bun_cache_path_rejects_command_delimiter_injection
    test_bun_cache_path_rejects_symlink_escape
    test_bun_cache_path_rejects_arbitrary_home_directory
    test_dev_prune_dry_run_and_gomi_safety
    test_dev_prune_refuses_broad_roots
    test_low_power_mode_forces_plain_and_disables_notification_noise
    test_log_files_are_unique_and_private
    test_log_directory_with_spaces_is_preserved
    test_mas_warning_rows_are_redacted_in_logs
    test_invalid_uv_timeout_override_warns_and_fallbacks
    test_cache_mixed_results
    test_mas_failure_logs_stderr
    test_mas_update_runs_without_account_preflight
    test_interrupt_reporting
    test_interrupt_stops_mas_inventory_child
    test_interrupt_stops_parallel_brew_outdated_children
    test_dev_prune_rejects_symlink_at_execution
    test_autoload_resolution
)
for _freshen_test_name in ${(ok)functions[(I)test_*]}; do
    (( ${_freshen_invoked_tests[(Ie)$_freshen_test_name]} )) && continue
    "$_freshen_test_name"
done

print "1..${TESTS_RUN}"
if (( TESTS_FAILED > 0 )); then
    exit 1
fi
