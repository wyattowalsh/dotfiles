# Case pack: Darwin tmutil listing is report-only and non-fatal

test_storage_plan_tmutil_failure_is_nonfatal() {
    setup_env storage-plan-tmutil
    command rm -f "${TEST_BIN}/brew"
    write_tool_stub tmutil
    export STUB_RC_TMUTIL=1
    local empty_root="${TEST_ROOT}/empty-dev"
    mkdir -p "$empty_root"
    local out="${TEST_ROOT}/storage-plan-tmutil.out"

    run_freshen "$out" --storage-plan --dev-prune-root="$empty_root" --no-color
    assert_status 0 $? "tmutil failure does not fail storage-plan"
    if [[ "$(uname -s)" == Darwin ]]; then
        assert_contains "$out" "Time Machine:" "Darwin storage-plan reports Time Machine"
        assert_contains "$TRACE_FILE" "tmutil destinationinfo" "Time Machine probe is destinationinfo"
        assert_not_contains "$TRACE_FILE" "thinlocalsnapshots" "storage-plan does not thin TM snapshots"
    else
        pass "Time Machine probe skipped off Darwin"
        pass "Time Machine listing not required off Darwin"
        pass "Time Machine thin not invoked off Darwin"
    fi
}
