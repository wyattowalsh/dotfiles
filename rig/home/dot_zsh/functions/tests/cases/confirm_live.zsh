# Case pack: confirm restore + live INT (RV-S-001 / RV-S-004)

test_confirm_proceed_restores_inventory_state() {
    setup_env confirm-restore
    export FRESHEN_FORCE_INTERACTIVE=1
    export FRESHEN_CONFIRM_REPLY=y
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_FORMULA_SINGLE_OUTPUT_ALPHA=$'==> Upgrading alpha\nalpha 1.0 -> 1.1'
    local out="${TEST_ROOT}/confirm-restore.out"

    run_freshen "$out" --formula-only --no-mas --no-cleanup --no-cache --progress=plain --no-color
    assert_status 0 $? "confirm-y proceed exits cleanly without --yes"
    assert_not_contains "$out" "Non-interactive — use --yes to proceed" "force-interactive skips the non-interactive guard"
    assert_contains "$out" "W Inventory: waiting — confirmation prompt" "confirm still surfaces a waiting line"
    if python3 -c '
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
idx = text.find("Proceed?")
sys.exit(0 if idx >= 0 and "Inventory: waiting" not in text[idx:] else 1)
' "$out"; then
        pass "inventory is not left waiting after proceed"
    else
        print -u2 -r -- "inventory still waiting after Proceed?"
        fail "inventory is not left waiting after proceed"
    fi
    assert_contains "$out" "Proceed?" "confirm prompt is shown"
    assert_contains "$TRACE_FILE" "brew upgrade alpha" "confirm-y still runs the upgrade"
}

test_confirm_live_pauses_before_proceed_prompt() {
    setup_env confirm-live-pause
    export FRESHEN_FORCE_LIVE=1
    export FRESHEN_FORCE_INTERACTIVE=1
    export FRESHEN_CONFIRM_REPLY=y
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_FORMULA_SINGLE_OUTPUT_ALPHA=$'==> Upgrading alpha\nalpha 1.0 -> 1.1'
    local out="${TEST_ROOT}/confirm-live-pause.out"

    run_freshen "$out" --formula-only --no-mas --no-cleanup --no-cache --progress=live --no-color
    assert_status 0 $? "live confirm-y exits cleanly"
    if python3 -c '
import re, sys
from pathlib import Path
data = Path(sys.argv[1]).read_bytes()
needle = b"Proceed?"
idx = data.find(needle)
if idx < 0:
    sys.exit(1)
window = data[:idx]
# The leave immediately before Proceed? must not be followed by a re-enter.
last_leave = window.rfind(b"\x1b[?1049l")
last_enter = window.rfind(b"\x1b[?1049h")
sys.exit(0 if last_leave >= 0 and last_leave > last_enter else 2)
' "$out"; then
        pass "live leaves the alt-screen before Proceed? without re-entering"
    else
        print -u2 -r -- "Proceed? missing or alt-screen re-entered before it"
        print -u2 -r -- "--- file: $out ---"
        sed -n '1,220p' "$out" >&2
        fail "live leaves the alt-screen before Proceed? without re-entering"
    fi
}

test_confirm_cancel_does_not_upgrade() {
    setup_env confirm-cancel
    export FRESHEN_FORCE_INTERACTIVE=1
    export FRESHEN_CONFIRM_REPLY=n
    export BREW_OUTDATED_FORMULAE='alpha'
    local out="${TEST_ROOT}/confirm-cancel.out"

    run_freshen "$out" --formula-only --no-mas --no-cleanup --no-cache --progress=plain --no-color
    assert_status 0 $? "confirm-n cancel exits 0"
    assert_contains "$out" "Cancelled" "cancel is reported"
    assert_not_contains "$TRACE_FILE" "brew upgrade alpha" "cancel does not upgrade"
}

test_live_interrupt_leaves_alt_screen() {
    setup_env live-interrupt
    export FRESHEN_FORCE_LIVE=1
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_FORMULA_SINGLE_SLEEP_ALPHA=10
    local out="${TEST_ROOT}/live-interrupt.out"
    local rc=0

    PATH="${TEST_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="${TEST_HOME}" \
    XDG_STATE_HOME="${TEST_STATE}" \
    TMPDIR="${TEST_TMP}" \
    TRACE_FILE="${TRACE_FILE}" \
    FRESHEN_UNDER_TEST="${FRESHEN_UNDER_TEST:-$FRESHEN_FILE}" \
    FRESHEN_FORCE_LIVE=1 \
    zsh -fc 'fpath=("$1" $fpath); autoload -Uz freshen; shift; freshen "$@"' zsh "$FRESHEN_DIR" \
        --yes --no-mas --no-cleanup --no-cache --progress=live --no-color >"$out" 2>&1 &
    local runner_pid=$!
    local tries=0
    while (( tries < 50 )) && ! grep -Fq -- "brew upgrade alpha" "$TRACE_FILE"; do
        sleep 0.1
        (( tries++ ))
    done
    kill -INT "$runner_pid"
    wait "$runner_pid" || rc=$?

    assert_interrupt_status "$rc" "live interrupt returns 130 or 143"
    if python3 -c '
import re, sys
from pathlib import Path
data = Path(sys.argv[1]).read_bytes()
enters = [m.start() for m in re.finditer(rb"\x1b\[\?1049h", data)]
leaves = [m.start() for m in re.finditer(rb"\x1b\[\?1049l", data)]
sys.exit(0 if enters and leaves and leaves[-1] > enters[-1] else 1)
' "$out"; then
        pass "live interrupt does not re-enter the alt-screen after the final leave"
    else
        print -u2 -r -- "live interrupt alt-screen pairing failed"
        print -u2 -r -- "--- file: $out ---"
        sed -n '1,220p' "$out" >&2
        fail "live interrupt does not re-enter the alt-screen after the final leave"
    fi
}
