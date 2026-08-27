# Case pack: live dashboard hygiene (force-live test hook; no PTY required)

assert_live_tail_contains() {
    local file="$1" needle="$2" label="$3"
    if python3 -c '
import re, sys
from pathlib import Path
data = Path(sys.argv[1]).read_bytes()
needle = sys.argv[2].encode()
pat = re.compile(rb"\x1b\[\?1049[hl]|\x1b\[\?25[lh]|\x1b\[H\x1b\[2J|\x1b\[H\x1b\[J|\x1b\[2J")
last = None
for m in pat.finditer(data):
    last = m
tail = data[last.end():] if last else data
sys.exit(0 if needle in tail else 1)
' "$file" "$needle"; then
        pass "$label"
    else
        print -u2 -r -- "expected live tail to contain: $needle"
        print -u2 -r -- "--- file: $file ---"
        sed -n '1,220p' "$file" >&2
        fail "$label"
    fi
}



assert_bytes_order() {
    local file="$1" first="$2" second="$3" label="$4"
    if python3 -c '
import sys
from pathlib import Path
data = Path(sys.argv[1]).read_bytes()
a = sys.argv[2].encode("utf-8").decode("unicode_escape").encode()
b = sys.argv[3].encode("utf-8").decode("unicode_escape").encode()
ia, ib = data.find(a), data.find(b)
sys.exit(0 if ia >= 0 and ib >= 0 and ia < ib else 1)
' "$file" "$first" "$second"; then
        pass "$label"
    else
        print -u2 -r -- "expected order: $first  then  $second"
        print -u2 -r -- "--- file: $file ---"
        sed -n '1,220p' "$file" >&2
        fail "$label"
    fi
}

test_help_documents_force_live() {
    setup_env help-force-live
    local out="${TEST_ROOT}/help-force-live.out"
    run_freshen "$out" --help --no-color
    assert_status 0 $? "help still exits cleanly"
    assert_contains "$out" "FRESHEN_FORCE_LIVE" "help documents FRESHEN_FORCE_LIVE"
}

test_force_live_does_not_override_plain() {
    setup_env force-live-plain
    export FRESHEN_FORCE_LIVE=1
    local out="${TEST_ROOT}/force-live-plain.out"

    run_freshen "$out" --dry-run --yes --progress=plain --no-mas --no-color
    assert_status 0 $? "force-live plus plain dry-run exits cleanly"
    assert_not_contains "$out" $'\e[' "force-live does not inject ANSI into --progress=plain --no-color"
}

test_force_live_does_not_override_low_power() {
    setup_env force-live-low-power
    export FRESHEN_FORCE_LIVE=1
    export FRESHEN_LOW_POWER=1
    local out="${TEST_ROOT}/force-live-low-power.out"

    run_freshen "$out" --dry-run --yes --progress=live --no-mas --no-color
    assert_status 0 $? "force-live plus low-power dry-run exits cleanly"
    assert_not_contains "$out" $'\e[?25l' "low-power still wins over FRESHEN_FORCE_LIVE"
    assert_not_contains "$out" $'\e[?1049h' "low-power does not enter the live alt-screen"
}

test_live_waiting_does_not_append_phase_line() {
    setup_env live-waiting-no-append
    export FRESHEN_FORCE_LIVE=1
    export BREW_OUTDATED_CASKS='firefox'
    export BREW_CASK_SINGLE_OUTPUT_FIREFOX=$'==> Upgrading Cask firefox\nfirefox: 1.0 -> 1.1'
    local out="${TEST_ROOT}/live-waiting-no-append.out"

    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --progress=live --no-color
    assert_status 0 $? "forced live cask run exits cleanly"
    assert_contains "$out" $'\e[?1049h' "forced live enters the alt-screen dashboard"
    assert_contains "$out" "Casks  waiting" "live dashboard rendered the waiting cask state"
    assert_not_contains "$out" "  W Casks: waiting — validating sudo for cask installers" \
        "live waiting does not append the lines-mode waiting row"
    local log_path
    log_path="$(find_log_path "$out")"
    if [[ -n "$log_path" && -f "$log_path" ]]; then
        assert_contains "$log_path" "WAITING validating sudo for cask installers" \
            "sudo waiting is still logged"
    else
        print -u2 -r -- "missing log path in live waiting output"
        fail "sudo waiting is still logged"
    fi
}

test_live_pauses_alt_screen_before_sudo_prompt() {
    setup_env live-sudo-pause
    export FRESHEN_FORCE_LIVE=1
    export BREW_OUTDATED_CASKS='firefox'
    export BREW_CASK_SINGLE_OUTPUT_FIREFOX=$'==> Upgrading Cask firefox\nfirefox: 1.0 -> 1.1'
    local out="${TEST_ROOT}/live-sudo-pause.out"

    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --progress=live --no-color
    assert_status 0 $? "forced live sudo path exits cleanly"
    assert_contains "$TRACE_FILE" "sudo -v" "live sudo path still validates sudo"
    assert_bytes_order "$out" '\x1b[?1049l' 'Cask installers may need admin privileges' \
        "live leaves the alt-screen before the sudo preflight message"
}

test_live_summary_survives_after_dashboard_close() {
    setup_env live-summary-survives
    export FRESHEN_FORCE_LIVE=1
    export BREW_OUTDATED_CASKS='firefox'
    export BREW_CASK_SINGLE_OUTPUT_FIREFOX=$'==> Upgrading Cask firefox\nfirefox: 1.0 -> 1.1'
    local out="${TEST_ROOT}/live-summary-survives.out"

    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --progress=live --no-color
    assert_status 0 $? "forced live summary path exits cleanly"
    assert_live_tail_contains "$out" "Summary" "Summary remains after the last live screen control"
    assert_live_tail_contains "$out" "Casks: done" "phase summary lines print after live close"
    if python3 -c '
import re, sys
from pathlib import Path
data = Path(sys.argv[1]).read_bytes()
enters = [m.start() for m in re.finditer(rb"\x1b\[\?1049h", data)]
leaves = [m.start() for m in re.finditer(rb"\x1b\[\?1049l", data)]
sys.exit(0 if enters and leaves and leaves[-1] > enters[-1] else 1)
' "$out"; then
        pass "live does not re-enter the alt-screen after the final leave"
    else
        print -u2 -r -- "alt-screen enter/leave pairing failed"
        print -u2 -r -- "--- file: $out ---"
        sed -n '1,220p' "$out" >&2
        fail "live does not re-enter the alt-screen after the final leave"
    fi
}

test_live_does_not_paint_gomi_error_on_alt_screen() {
    setup_env live-gomi-err-offscreen
    export FRESHEN_FORCE_LIVE=1
    local project_root="${TEST_ROOT}/project"
    local modules_dir="${project_root}/node_modules"
    mkdir -p "$modules_dir"
    freshen_stamp_mtime_days_ago "$modules_dir" 20 || fail "stamp mtime 20d"
    local out="${TEST_ROOT}/live-gomi-err.out"

    run_freshen "$out" --clean-only --yes --no-cleanup --dev-prune --dev-prune-root="$project_root" --progress=live --no-color
    assert_status 1 $? "missing gomi still degrades under FORCE_LIVE"
    assert_contains "$out" "gomi is required" "gomi refusal is still visible after the board"
    if python3 -c '
import re, sys
from pathlib import Path
data = Path(sys.argv[1]).read_bytes()
needle = b"gomi is required"
if needle not in data:
    sys.exit(1)
leaves = [m.end() for m in re.finditer(rb"\x1b\[\?1049l", data)]
tail = data[leaves[-1]:] if leaves else data
sys.exit(0 if needle in tail else 2)
' "$out"; then
        pass "gomi refusal remains in the recap after live leave"
    else
        print -u2 -r -- "gomi refusal missing from recap tail"
        fail "gomi refusal remains in the recap after live leave"
    fi
}

assert_no_reenter_between_leave_and_needle() {
    local file="$1" needle="$2" label="$3"
    if python3 -c '
import sys
from pathlib import Path
data = Path(sys.argv[1]).read_bytes()
needle = sys.argv[2].encode()
idx = data.find(needle)
if idx < 0:
    sys.exit(1)
window = data[:idx]
last_leave = window.rfind(b"\x1b[?1049l")
last_enter = window.rfind(b"\x1b[?1049h")
sys.exit(0 if last_leave >= 0 and last_leave > last_enter else 2)
' "$file" "$needle"; then
        pass "$label"
    else
        print -u2 -r -- "expected leave immediately before: $needle"
        print -u2 -r -- "--- file: $file ---"
        sed -n '1,220p' "$file" >&2
        fail "$label"
    fi
}

test_live_sudo_fail_prints_later_phase_lines() {
    setup_env live-sudo-fail-later
    export FRESHEN_FORCE_LIVE=1
    export BREW_OUTDATED_CASKS='firefox'
    export SUDO_RC=1
    local out="${TEST_ROOT}/live-sudo-fail-later.out"

    run_freshen "$out" --yes --cask-only --no-mas --no-cache --progress=live --no-color
    assert_status 1 $? "live sudo preflight failure exits non-zero"
    assert_contains "$out" "sudo preflight failed" "sudo failure is visible"
    assert_contains "$out" "Casks: failed" "casks lane is failed"
    assert_contains "$out" "Cleanup:" "later cleanup phase still prints after sudo abort"
    assert_contains "$out" "Attention" "degraded recap still has Attention"
}

test_live_sudo_csi_does_not_reenter_before_prompt() {
    setup_env live-sudo-csi-order
    export FRESHEN_FORCE_LIVE=1
    export BREW_OUTDATED_CASKS='firefox'
    export BREW_CASK_SINGLE_OUTPUT_FIREFOX=$'==> Upgrading Cask firefox\nfirefox: 1.0 -> 1.1'
    local out="${TEST_ROOT}/live-sudo-csi-order.out"

    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --progress=live --no-color
    assert_status 0 $? "live sudo success path still exits cleanly"
    assert_no_reenter_between_leave_and_needle "$out" "Cask installers may need admin privileges" \
        "no alt-screen re-enter between leave and sudo preflight message"
}

test_force_live_verbose_keeps_dashboard_quiet_still_demotes() {
    setup_env force-live-demote
    export FRESHEN_FORCE_LIVE=1
    local out="${TEST_ROOT}/force-live-verbose.out"
    run_freshen "$out" --dry-run --yes --verbose --progress=live --no-mas --no-color
    assert_status 0 $? "force-live plus verbose dry-run exits cleanly"
    assert_contains "$out" $'\e[?1049h' "verbose does not disable live"

    local outq="${TEST_ROOT}/force-live-quiet.out"
    run_freshen "$outq" --dry-run --yes --quiet --progress=live --no-mas --no-color
    assert_status 0 $? "force-live plus quiet dry-run exits cleanly"
    assert_not_contains "$outq" $'\e[?1049h' "quiet still wins over FRESHEN_FORCE_LIVE"
}

test_force_live_auto_still_lives_under_test() {
    setup_env force-live-auto
    export FRESHEN_FORCE_LIVE=1
    export BREW_OUTDATED_CASKS='firefox'
    export BREW_CASK_SINGLE_OUTPUT_FIREFOX=$'==> Upgrading Cask firefox\nfirefox: 1.0 -> 1.1'
    local out="${TEST_ROOT}/force-live-auto.out"

    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --progress=auto --no-color
    assert_status 0 $? "force-live auto under test exits cleanly"
    assert_contains "$out" $'\e[?1049h' "FRESHEN_FORCE_LIVE still forces auto live under test"
}

test_plain_apply_has_no_bell() {
    setup_env plain-apply-no-bell
    export FRESHEN_FORCE_INTERACTIVE=1
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_FORMULA_SINGLE_OUTPUT_ALPHA=$'==> Upgrading alpha\nalpha 1.0 -> 1.1'
    local out="${TEST_ROOT}/plain-apply-no-bell.out"

    run_freshen "$out" --yes --formula-only --no-mas --no-cleanup --no-cache --progress=plain --no-color
    assert_status 0 $? "plain apply exits cleanly"
    assert_not_contains "$out" $'\a' "plain apply does not emit a terminal bell"
    assert_not_contains "$out" $'\e[' "plain apply still has no ANSI escapes"
}

test_live_title_respects_no_emoji() {
    setup_env live-no-emoji
    export FRESHEN_FORCE_LIVE=1
    export FRESHEN_NO_EMOJI=1
    export BREW_OUTDATED_CASKS='firefox'
    export BREW_CASK_SINGLE_OUTPUT_FIREFOX=$'==> Upgrading Cask firefox\nfirefox: 1.0 -> 1.1'
    local out="${TEST_ROOT}/live-no-emoji.out"

    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --progress=live --no-color
    assert_status 0 $? "no-emoji live run exits cleanly"
    assert_not_contains "$out" "🍃" "live title respects FRESHEN_NO_EMOJI"
}
