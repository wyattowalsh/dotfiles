# RV-002: trust plan must not claim non-mutating if brew update runs

test_print_trust_plan_copy_is_honest_about_update() {
    setup_env trust-plan-copy
    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --print-trust-plan --progress=plain --no-color
    assert_status 0 $? "print-trust-plan exits cleanly"
    assert_contains "$TRACE_FILE" "brew update" "trust plan runs brew update"
    assert_not_contains "$out" "non-mutating" "must not claim non-mutating when update runs"
    assert_contains "$out" "brew update" "UI mentions brew update side effect"
}

test_help_print_trust_plan_not_non_mutating() {
    setup_env trust-plan-help
    local out="${TEST_ROOT}/help.txt"
    run_freshen "$out" --help --no-color
    assert_status 0 $? "help exits cleanly"
    assert_contains "$out" "--print-trust-plan" "help documents --print-trust-plan"
    assert_not_contains "$out" "non-mutating" "help does not call trust plan non-mutating"
}
