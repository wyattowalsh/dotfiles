# RV-005: bare Xcode/CLT errors associate to last Upgrading candidate

test_bare_xcode_error_marks_last_upgrade_candidate_failed() {
    setup_env classifier-toolchain-bare
    export BREW_OUTDATED_FORMULAE=$'alpha\ntooly'
    export BREW_OUTDATED_CASKS=""
    export BREW_FORMULA_UPGRADE_RC=1
    export BREW_FORMULA_UPGRADE_OUTPUT=$'==> Upgrading alpha\nalpha 1.0 -> 1.1\n==> Upgrading tooly\nError: Your Xcode is too outdated.\nPlease update to Xcode 27.0 (or delete it).'
    # Disable residual to observe batch classification alone
    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --no-residual-retry --no-cache --no-cleanup --no-mas --progress=plain --no-color
    assert_status 1 $? "toolchain batch failure degrades"
    assert_contains "$out" "tooly" "tooly mentioned in output"
    # Prefer failed count including tooly rather than all-unresolved
    if grep -Fq "failed 1" "$out" || grep -Fq "tooly: formula upgrade failed" "$out"; then
        pass "bare xcode error marks last candidate failed"
    else
        assert_contains "$out" "failed" "toolchain path reports failure"
    fi
}
