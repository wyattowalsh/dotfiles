# RV-001 / RV-008: residual confirmation must not false-promote

test_residual_outdated_inventory_fail_does_not_confirm() {
    setup_env residual-outdated-fail
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_OUTDATED_CASKS=""
    # Batch has no recognizable per-pkg upgrade lines → residual retries alpha
    export BREW_FORMULA_UPGRADE_OUTPUT='Pouring unrelated bottle output'
    export BREW_FORMULA_UPGRADE_RC=0
    # Residual single upgrade exits 0 with no exact markers
    export BREW_FORMULA_SINGLE_OUTPUT_ALPHA='done'
    export BREW_FORMULA_SINGLE_RC_ALPHA=0
    # Subsequent outdated calls fail (inventory unavailable)
    export BREW_OUTDATED_FORMULAE_LATER=""
    export BREW_OUTDATED_FORMULAE_LATER_RC=1

    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --no-cache --no-cleanup --no-mas --progress=plain --no-color
    assert_status 1 $? "outdated inventory failure keeps run degraded"
    assert_contains "$TRACE_FILE" "brew upgrade alpha" "residual retries unresolved package"
    assert_not_contains "$out" "confirmed 1" "must not confirm residual when outdated inventory fails"
}

test_residual_unrelated_pouring_does_not_confirm_while_still_outdated() {
    setup_env residual-pouring-only
    export BREW_OUTDATED_FORMULAE='alpha'
    export BREW_OUTDATED_CASKS=""
    export BREW_FORMULA_UPGRADE_OUTPUT='Pouring unrelated bottle output'
    export BREW_FORMULA_UPGRADE_RC=0
    export BREW_FORMULA_SINGLE_OUTPUT_ALPHA='Pouring some-dep--1.0.bottle.tar.gz'
    export BREW_FORMULA_SINGLE_RC_ALPHA=0
    # Later outdated still lists alpha (trusted rc=0)
    export BREW_OUTDATED_FORMULAE_LATER='alpha'
    export BREW_OUTDATED_FORMULAE_LATER_RC=0

    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --no-cache --no-cleanup --no-mas --progress=plain --no-color
    assert_status 1 $? "still-outdated residual does not succeed overall"
    assert_contains "$out" "Residual:" "residual pass ran"
    assert_not_contains "$out" "Formulae: done" "formulae lane not fully done on pouring-only residual"
}
