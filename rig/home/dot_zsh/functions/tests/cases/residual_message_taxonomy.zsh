# RV-S-001: residual outcome messages must not claim "upgrade failed" on rc=0

test_residual_rc0_still_outdated_warns_not_err() {
    setup_env residual-msg-still-out
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_OUTDATED_CASKS=""
    export BREW_FORMULA_UPGRADE_OUTPUT='Pouring unrelated bottle output'
    export BREW_FORMULA_UPGRADE_RC=0
    export BREW_FORMULA_SINGLE_OUTPUT_ALPHA='Pouring some-dep--1.0.bottle.tar.gz'
    export BREW_FORMULA_SINGLE_RC_ALPHA=0
    export BREW_OUTDATED_FORMULAE_LATER='alpha'
    export BREW_OUTDATED_FORMULAE_LATER_RC=0

    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --no-cache --no-cleanup --no-mas --progress=plain --no-color
    assert_status 1 $? "still-outdated residual keeps run non-zero"
    assert_contains "$out" "Residual:" "residual pass ran"
    assert_not_contains "$out" "upgrade failed (rc=0)" "must not claim upgrade failed when rc=0"
    assert_contains "$out" "not confirmed (still outdated)" "warns residual not confirmed still outdated"
    assert_not_contains "$out" "Formulae: done" "formulae lane not fully done when still outdated"
}

test_residual_rc0_inventory_fail_warns_not_err() {
    setup_env residual-msg-inv-fail
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_OUTDATED_CASKS=""
    export BREW_FORMULA_UPGRADE_OUTPUT='Pouring unrelated bottle output'
    export BREW_FORMULA_UPGRADE_RC=0
    export BREW_FORMULA_SINGLE_OUTPUT_ALPHA='done'
    export BREW_FORMULA_SINGLE_RC_ALPHA=0
    export BREW_OUTDATED_FORMULAE_LATER=""
    export BREW_OUTDATED_FORMULAE_LATER_RC=1

    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --no-cache --no-cleanup --no-mas --progress=plain --no-color
    assert_status 1 $? "inventory-fail residual keeps run non-zero"
    assert_contains "$TRACE_FILE" "brew upgrade alpha" "residual retries unresolved package"
    assert_not_contains "$out" "upgrade failed (rc=0)" "must not claim upgrade failed when rc=0"
    assert_contains "$out" "not confirmed (outdated inventory failed)" "warns residual not confirmed inventory failed"
    assert_not_contains "$out" "confirmed 1" "must not confirm residual when inventory fails"
}

test_residual_command_fail_still_errs() {
    setup_env residual-msg-cmd-fail
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_OUTDATED_CASKS=""
    export BREW_FORMULA_UPGRADE_OUTPUT='Pouring unrelated bottle output'
    export BREW_FORMULA_UPGRADE_RC=0
    export BREW_FORMULA_SINGLE_OUTPUT_ALPHA='Error: install failed hard'
    export BREW_FORMULA_SINGLE_RC_ALPHA=2
    export BREW_OUTDATED_FORMULAE_LATER='alpha'
    export BREW_OUTDATED_FORMULAE_LATER_RC=0

    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --no-cache --no-cleanup --no-mas --progress=plain --no-color
    assert_status 1 $? "command-fail residual keeps run non-zero"
    assert_contains "$out" "upgrade failed (rc=2)" "true residual command failure still reports failed rc"
}
