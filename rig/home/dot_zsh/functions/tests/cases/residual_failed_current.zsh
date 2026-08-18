# AGENTS invariant: failed+current → leave failed, no residual retry
# (do not promote like unknown+current; do not sequential-retry).

test_residual_failed_current_leaves_failed_no_retry() {
    setup_env residual-failed-current
    export BREW_OUTDATED_FORMULAE=$'alpha\nbeta'
    export BREW_OUTDATED_CASKS=""
    export BREW_FORMULA_UPGRADE_OUTPUT=$'==> Upgrading alpha\nalpha 1.0 -> 1.1\nError: beta failed during: install'
    export BREW_FORMULA_UPGRADE_RC=1
    # If residual wrongly retries, this would confirm beta.
    export BREW_FORMULA_SINGLE_OUTPUT_BETA=$'==> Upgrading beta\nbeta 1.0 -> 1.1'
    export BREW_FORMULA_SINGLE_RC_BETA=0
    # After batch, inventory succeeds and omits beta (current).
    export BREW_OUTDATED_FORMULAE_LATER=""
    export BREW_OUTDATED_FORMULAE_LATER_RC=0

    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --no-cache --no-cleanup --no-mas --progress=plain --no-color
    assert_status 1 $? "failed+current keeps the run non-zero"
    assert_contains "$TRACE_FILE" "brew upgrade alpha beta" "batch upgrade attempted both packages"
    assert_not_contains "$TRACE_FILE" "brew upgrade beta" "failed+current must not residual-retry beta"
    assert_not_contains "$out" "Residual:" "failed+current must not start a residual pass"
    assert_contains "$out" "failed 1" "beta stays failed (not promoted to confirmed)"
    assert_contains "$out" "beta: formula upgrade failed" "batch failure for beta is retained"
    assert_contains "$out" "failed formulae package(s) no longer outdated" "prepare reports skipped failed-current packages"
}
