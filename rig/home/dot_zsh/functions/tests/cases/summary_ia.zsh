# Case pack: end-of-run IA — Attention / Next actions before phase Summary

assert_heading_order() {
    local file="$1" first="$2" second="$3" label="$4"
    if python3 -c '
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()

def pos(heading):
    m = re.search(r"(?m)^ {0,2}" + re.escape(heading) + r"$", text)
    return m.start() if m else -1

ia, ib = pos(sys.argv[2]), pos(sys.argv[3])
sys.exit(0 if ia >= 0 and ib >= 0 and ia < ib else 1)
' "$file" "$first" "$second"; then
        pass "$label"
    else
        print -u2 -r -- "expected heading ${first} before ${second}"
        print -u2 -r -- "--- file: $file ---"
        sed -n '1,220p' "$file" >&2
        fail "$label"
    fi
}

test_attention_and_next_actions_precede_phase_summary() {
    setup_env summary-ia-sudo
    export BREW_OUTDATED_CASKS='firefox'
    export SUDO_RC=1
    local out="${TEST_ROOT}/summary-ia-sudo.out"

    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --progress=plain --no-color
    assert_status 1 $? "sudo preflight failure still exits non-zero"
    assert_contains "$out" "Attention" "degraded run still has Attention"
    assert_contains "$out" "Next actions" "degraded run still has Next actions"
    assert_contains "$out" "Summary" "degraded run still has phase Summary"
    assert_heading_order "$out" "Attention" "Next actions" "Attention precedes Next actions"
    assert_heading_order "$out" "Next actions" "Summary" "Next actions precede phase Summary"
    assert_heading_order "$out" "Attention" "Summary" "Attention precedes phase Summary"
}

test_help_start_here_layers_before_full_flags() {
    setup_env help-start-here
    local out="${TEST_ROOT}/help-start-here.out"

    run_freshen "$out" --help --no-color
    assert_status 0 $? "help still exits cleanly"
    assert_contains "$out" "START HERE" "help has a short start-here card"
    assert_contains "$out" "Attention and Next actions" "help documents end-of-run Attention-first order"
    assert_contains "$out" "alt-screen" "help documents live alt-screen"
    assert_heading_order "$out" "START HERE" "USAGE" "start-here card precedes full USAGE"
    assert_heading_order "$out" "START HERE" "FLAGS" "start-here card precedes FLAGS"
}

test_degraded_recap_always_includes_review_log() {
    setup_env recap-review-log
    export BREW_OUTDATED_CASKS='firefox'
    export SUDO_RC=1
    local out="${TEST_ROOT}/recap-review-log.out"

    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --no-residual-retry --progress=plain --no-color
    assert_status 1 $? "sudo failure still degrades"
    assert_contains "$out" "Review log" "recap always includes Review log"
    assert_contains "$out" "freshen -L -Y --progress=lines --no-color" "cask failure with residual retry off suggests sequential upgrades"
}

test_clean_only_cache_failure_skips_sequential_upgrade_hint() {
    setup_env recap-cache-no-seq
    export STUB_RC_GEM=1
    mkdir -p "${TEST_HOME}/.bun/install/cache"
    local out="${TEST_ROOT}/recap-cache-no-seq.out"

    run_freshen "$out" --clean-only --yes --no-cleanup --gem-cleanup --progress=plain --no-color
    assert_status 1 $? "cache failure still degrades"
    assert_contains "$out" "Attention" "cache failure still has Attention"
    assert_not_contains "$out" "sequential upgrades" "cache-only degrade does not suggest sequential upgrades"
}

test_help_start_here_and_force_live_are_test_accurate() {
    setup_env help-findings-copy
    local out="${TEST_ROOT}/help-findings-copy.out"
    run_freshen "$out" --help --no-color
    assert_status 0 $? "help still exits cleanly"
    assert_contains "$out" "Degraded apply" "START HERE scopes Attention-first to apply runs"
    assert_contains "$out" "FRESHEN_UNDER_TEST" "FORCE_LIVE help is labeled for the test harness"
    assert_contains "$out" "FRESHEN_FORCE_INTERACTIVE" "help documents FRESHEN_FORCE_INTERACTIVE"
    assert_contains "$out" "FRESHEN_CONFIRM_REPLY" "help documents FRESHEN_CONFIRM_REPLY"
}
