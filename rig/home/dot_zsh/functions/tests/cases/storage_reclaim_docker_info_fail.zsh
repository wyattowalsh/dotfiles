# Case pack: failed docker info must not run system df

test_storage_plan_docker_info_fail_skips_df() {
    setup_env storage-plan-docker-info-fail
    command rm -f "${TEST_BIN}/brew"
    export STUB_DOCKER_INFO_RC=1
    local empty_root="${TEST_ROOT}/empty-dev"
    mkdir -p "$empty_root"
    local out="${TEST_ROOT}/storage-plan-docker-info-fail.out"

    run_freshen "$out" --storage-plan --dev-prune-root="$empty_root" --no-color
    assert_status 0 $? "failed docker info still leaves storage-plan at 0"
    assert_contains "$TRACE_FILE" "docker info" "storage-plan probes docker info"
    assert_not_contains "$TRACE_FILE" "docker system df" "failed docker info skips system df"
    assert_not_contains "$TRACE_FILE" "docker system prune" "failed docker info does not prune"
}
