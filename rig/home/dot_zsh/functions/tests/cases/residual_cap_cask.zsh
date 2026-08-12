# RV-S-005: residual cap next-action must be lane-aware for casks (hard assert)

test_residual_cap_cask_next_action_uses_k_not_f() {
    setup_env residual-cap-cask
    export FRESHEN_RESIDUAL_MAX=1
    export BREW_OUTDATED_FORMULAE=""
    export BREW_OUTDATED_CASKS=$'firefox\nraycast'
    # Neither confirmed in batch → residual candidates = 2, cap truncates to 1
    export BREW_CASK_UPGRADE_RC=1
    export BREW_CASK_UPGRADE_OUTPUT='Error: batch failed for both casks'
    export BREW_CASK_SINGLE_OUTPUT_FIREFOX='Error: still broken'
    export BREW_CASK_SINGLE_RC_FIREFOX=1
    export BREW_CASK_SINGLE_OUTPUT_RAYCAST='Error: still broken'
    export BREW_CASK_SINGLE_RC_RAYCAST=1
    # Keep both still outdated so prepare does not shrink below cap trigger
    export BREW_OUTDATED_CASKS_LATER=$'firefox\nraycast'
    export BREW_OUTDATED_CASKS_LATER_RC=0

    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --no-sudo-preflight --progress=plain --no-color
    assert_status 1 $? "cask residual cap path exits non-zero"
    assert_contains "$out" "remaining residual (cap hit)" "cask residual cap tip is emitted"
    assert_contains "$out" "freshen -K" "cask residual cap tip uses -K"
    assert_not_contains "$out" "freshen -F -L -Y --progress=lines --no-color  # remaining residual (cap hit)" \
        "cask residual cap must not suggest formula-only -F tip"
}
