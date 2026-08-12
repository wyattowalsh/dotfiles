# Residual sequential retry after a partial batch failure

test_residual_retry_runs_unresolved_formula() {
    setup_env residual-retry
    # Batch upgrades alpha then fails on beta; residual should retry beta alone.
    export BREW_OUTDATED_FORMULAE=$'alpha\nbeta'
    export BREW_OUTDATED_CASKS=""
    export BREW_FORMULA_UPGRADE_OUTPUT=$'==> Upgrading alpha\nalpha 1.0 -> 1.1\nError: beta failed during: install'
    export BREW_FORMULA_UPGRADE_RC=1
    export BREW_FORMULA_SINGLE_OUTPUT_BETA=$'==> Upgrading beta\nbeta 1.0 -> 1.1'
    export BREW_FORMULA_SINGLE_RC_BETA=0

    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --no-cache --no-cleanup --no-mas --progress=plain --no-color
    local rc=$?
    (( rc == 0 || rc == 1 )) || assert_status 0 "$rc" "residual path exits 0 or 1"
    assert_contains "$TRACE_FILE" "brew upgrade alpha beta" "batch upgrade attempted both packages"
    assert_contains "$TRACE_FILE" "brew upgrade beta" "residual sequential upgrade invoked for beta"
    assert_contains "$out" "Residual:" "residual banner shown"
}

test_no_residual_retry_flag_skips_residual_pass() {
    setup_env residual-retry-off
    export BREW_OUTDATED_FORMULAE=$'alpha\nbeta'
    export BREW_OUTDATED_CASKS=""
    export BREW_FORMULA_UPGRADE_OUTPUT=$'==> Upgrading alpha\nalpha 1.0 -> 1.1\nError: beta failed during: install'
    export BREW_FORMULA_UPGRADE_RC=1

    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --no-residual-retry --no-cache --no-cleanup --no-mas --progress=plain --no-color
    assert_not_contains "$out" "Residual:" "no residual banner when --no-residual-retry"
    assert_not_contains "$TRACE_FILE" "brew upgrade beta" "no single-package residual when disabled"
}
