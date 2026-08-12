# RV-S-002: cask residual must pre-filter still-outdated packages (parity with formulae)

test_cask_residual_prefilter_skips_current() {
    setup_env residual-cask-prefilter
    export BREW_OUTDATED_FORMULAE=""
    export BREW_OUTDATED_CASKS=$'firefox\nraycast'
    # Batch confirms neither (no upgrade markers) → both residual candidates
    export BREW_CASK_UPGRADE_RC=0
    export BREW_CASK_UPGRADE_OUTPUT='Done with no recognizable markers'
    # Prepare / later inventory: only raycast still outdated; firefox is current
    export BREW_OUTDATED_CASKS_LATER='raycast'
    export BREW_OUTDATED_CASKS_LATER_RC=0
    # Residual single for raycast confirms
    export BREW_CASK_SINGLE_OUTPUT_RAYCAST=$'==> Upgrading Cask raycast\nraycast: 1.0 -> 1.1'
    export BREW_CASK_SINGLE_RC_RAYCAST=0

    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --no-sudo-preflight --progress=plain --no-color
    local rc=$?
    (( rc == 0 || rc == 1 )) || assert_status 0 "$rc" "cask residual prefilter exits 0 or 1"
    # Default greedy path includes --greedy between --cask and package names.
    assert_contains "$TRACE_FILE" "brew upgrade --cask --greedy firefox raycast" "batch upgrade attempted both casks"
    assert_contains "$TRACE_FILE" "brew upgrade --cask --greedy raycast" "residual retries still-outdated raycast"
    if grep -E 'brew upgrade --cask( --greedy)? firefox$' "$TRACE_FILE" >/dev/null 2>&1; then
        fail "residual must not single-upgrade current firefox"
    else
        pass "residual must not single-upgrade current firefox"
    fi
}

test_cask_residual_prefilter_promotes_all_current() {
    setup_env residual-cask-promote-all
    export BREW_OUTDATED_FORMULAE=""
    export BREW_OUTDATED_CASKS=$'firefox\nraycast'
    export BREW_CASK_UPGRADE_RC=0
    export BREW_CASK_UPGRADE_OUTPUT='Done with no recognizable markers'
    # After batch, inventory says nothing outdated → promote unknowns, skip residual retries
    export BREW_OUTDATED_CASKS_LATER=""
    export BREW_OUTDATED_CASKS_LATER_RC=0

    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --no-sudo-preflight --progress=plain --no-color
    assert_status 0 $? "all-current after inventory promotes and succeeds"
    assert_contains "$out" "Casks: done" "casks lane done after promote-all-current"
    if grep -E 'brew upgrade --cask( --greedy)? (firefox|raycast)$' "$TRACE_FILE" >/dev/null 2>&1; then
        fail "no residual single upgrades when inventory empty"
    else
        pass "no residual single upgrades when inventory empty"
    fi
}
