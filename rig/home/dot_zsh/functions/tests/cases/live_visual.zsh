# Golden-frame tests: live must look like a dashboard, not seven unboxed phase lines.

test_live_visual_has_phase_and_now_panes() {
    setup_env live-visual-panes
    export FRESHEN_FORCE_LIVE=1
    export COLUMNS=100
    local out="${TEST_ROOT}/live-visual-panes.out"

    run_freshen "$out" --dry-run --yes --progress=live --no-mas --no-color
    assert_status 0 $? "live dry-run still exits cleanly"
    assert_contains "$out" $'╭' "live paints a rounded box"
    assert_contains "$out" "PHASES" "live paints a PHASES rail"
    assert_contains "$out" "NOW" "live paints a NOW pane"
}

test_live_visual_is_not_old_seven_row_dump() {
    setup_env live-visual-anti-old
    export FRESHEN_FORCE_LIVE=1
    export COLUMNS=100
    local out="${TEST_ROOT}/live-visual-anti-old.out"

    run_freshen "$out" --dry-run --yes --progress=live --no-mas --no-color
    assert_status 0 $? "anti-old live dry-run exits cleanly"
    if python3 -c '
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(errors="replace")
if "PHASES" not in text or "NOW" not in text or "╭" not in text:
    sys.exit(1)
# Old dump: Progress: [bar] then unboxed "  I Inventory:" / emoji rows, no box.
old_meter = bool(re.search(r"^Progress: \[", text, re.M))
old_unboxed_inventory = bool(re.search(r"^  .+ Inventory:", text, re.M))
if old_meter and old_unboxed_inventory and "PHASES" not in text.split("Inventory:")[0]:
    sys.exit(2)
sys.exit(0)
' "$out"; then
        pass "live dump is not the old seven-row unboxed list"
    else
        print -u2 -r -- "live dump still looks like the old phase list"
        sed -n '1,80p' "$out" >&2
        fail "live dump is not the old seven-row unboxed list"
    fi
}

test_plain_has_no_dashboard_chrome() {
    setup_env live-visual-plain
    export COLUMNS=100
    local out="${TEST_ROOT}/live-visual-plain.out"

    run_freshen "$out" --dry-run --yes --progress=plain --no-mas --no-color
    assert_status 0 $? "plain dry-run exits cleanly"
    assert_not_contains "$out" $'╭' "plain has no rounded box"
    assert_not_contains "$out" "PHASES" "plain has no PHASES rail"
    assert_not_contains "$out" "NOW" "plain has no NOW pane"
}

test_live_visual_narrow_still_has_panes() {
    setup_env live-visual-narrow
    export FRESHEN_FORCE_LIVE=1
    export COLUMNS=60
    local out="${TEST_ROOT}/live-visual-narrow.out"

    run_freshen "$out" --dry-run --yes --progress=live --no-mas --no-color
    assert_status 0 $? "narrow live dry-run exits cleanly"
    assert_contains "$out" "PHASES" "narrow live still labels PHASES"
    assert_contains "$out" "NOW" "narrow live still labels NOW"
}

test_live_recap_box_after_dashboard_close() {
    setup_env live-visual-recap
    export FRESHEN_FORCE_LIVE=1
    export COLUMNS=100
    export BREW_OUTDATED_CASKS='firefox'
    export SUDO_RC=1
    local out="${TEST_ROOT}/live-visual-recap.out"

    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --progress=live --no-color
    assert_status 1 $? "sudo failure still degrades"
    if python3 -c '
import re, sys
from pathlib import Path
data = Path(sys.argv[1]).read_bytes()
leaves = [m.end() for m in re.finditer(rb"\x1b\[\?1049l", data)]
tail = data[leaves[-1]:] if leaves else data
text = tail.decode("utf-8", "replace")
sys.exit(0 if "╭" in text and "Attention" in text else 1)
' "$out"; then
        pass "recap after live leave is boxed and Attention-first"
    else
        print -u2 -r -- "recap tail missing box or Attention"
        fail "recap after live leave is boxed and Attention-first"
    fi
}

test_live_default_is_dashboard_not_plan_dump() {
    setup_env live-default-dashboard
    export FRESHEN_FORCE_LIVE=1
    export COLUMNS=100
    local out="${TEST_ROOT}/live-default-dashboard.out"

    run_freshen "$out" --dry-run --yes --progress=auto --no-mas --no-color
    assert_status 0 $? "auto live dry-run exits cleanly"
    assert_contains "$out" "PHASES" "auto live still paints PHASES"
    assert_contains "$out" "NOW" "auto live still paints NOW"
    if python3 -c '
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(errors="replace")
sys.exit(1 if re.search(r"^  Plan$", text, re.M) else 0)
' "$out"; then
        pass "live does not dump the old Plan heading"
    else
        print -u2 -r -- "old Plan heading still present"
        fail "live does not dump the old Plan heading"
    fi
    assert_not_contains "$out" "🍃 freshen" "live does not print the old emoji banner"
}

test_bare_freshen_operator_defaults() {
    setup_env bare-operator-defaults
    mkdir -p "${TEST_HOME}/dev"
    export FRESHEN_FORCE_LIVE=1
    export COLUMNS=100
    local out="${TEST_ROOT}/bare-operator-defaults.out"

    run_freshen "$out"
    assert_not_contains "$out" "Proceed?" "bare freshen skips confirm (--yes)"
    assert_not_contains "$out" "not requested" "bare freshen enables doctor"
    assert_contains "$out" "PHASES" "bare freshen still uses live auto on FORCE_LIVE"
    assert_contains "$out" "NOW" "bare freshen still paints NOW"
    local log_path
    log_path="$(find_log_path "$out")"
    if [[ -n "$log_path" && -f "$log_path" ]]; then
        assert_contains "$log_path" "START Updating Homebrew metadata" "bare freshen is verbose in the log"
    else
        fail "bare freshen log path missing"
    fi
}

test_live_visual_uses_full_columns() {
    setup_env live-visual-wide
    export FRESHEN_FORCE_LIVE=1
    export COLUMNS=160
    local out="${TEST_ROOT}/live-visual-wide.out"
    run_freshen "$out" --dry-run --yes --progress=live --no-mas --no-color
    assert_status 0 $? "wide live dry-run exits cleanly"
    assert_contains "$out" "OVERALL" "live paints an OVERALL progress graph"
    assert_contains "$out" "brew:" "live has a brew detail section"
    if python3 -c '
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(errors="replace")
# Strip CSI
plain = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text)
width = 0
for line in plain.splitlines():
    if line.startswith("╭"):
        width = max(width, len(line))
sys.exit(0 if width >= 160 else 1)
' "$out"; then
        pass "live header spans COLUMNS=160"
    else
        print -u2 -r -- "live header shorter than 160 cols"
        fail "live header spans COLUMNS=160"
    fi
}

test_live_visual_shows_cask_and_overall() {
    setup_env live-visual-cask-info
    export FRESHEN_FORCE_LIVE=1
    export COLUMNS=160
    export BREW_OUTDATED_CASKS='firefox'
    export BREW_CASK_SINGLE_OUTPUT_FIREFOX=$'==> Upgrading Cask firefox\n==> Downloading https://example.invalid/firefox.dmg\n==> Installing Cask firefox\nfirefox: 1.0 -> 1.1'
    local out="${TEST_ROOT}/live-visual-cask-info.out"
    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --progress=live --no-color
    assert_status 0 $? "cask live run exits cleanly"
    assert_contains "$out" "OVERALL" "overall graph is present"
    assert_contains "$out" "firefox" "cask name is on the live board"
    assert_contains "$out" "packages" "package list header is present"
    assert_contains "$out" "brew:" "brew detail section is present"
    assert_contains "$out" "Downloading" "brew download line is surfaced"
}

test_live_visual_discovery_wave_nodes() {
    setup_env live-visual-waves
    export FRESHEN_FORCE_LIVE=1
    export COLUMNS=160
    export BREW_OUTDATED_CASKS='firefox'
    export BREW_OUTDATED_FORMULAE='wget'
    local out="${TEST_ROOT}/live-visual-waves.out"
    run_freshen "$out" --dry-run --yes --progress=live --no-mas --no-color
    assert_status 0 $? "discovery dry-run exits cleanly"
    assert_contains "$out" "OVERALL" "graph header present"
    assert_contains "$out" "○" "queued nodes appear after discovery"
    assert_contains "$out" "firefox" "cask wave includes discovered firefox"
    assert_contains "$out" "wget" "formulae wave includes discovered wget"
    assert_contains "$out" $'┌' "OVERALL fans out from inventory"
    assert_contains "$out" "cleanup" "graph sink includes cleanup"
}
