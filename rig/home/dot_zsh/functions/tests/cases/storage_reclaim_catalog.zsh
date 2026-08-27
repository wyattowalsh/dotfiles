# Case pack: catalog split (Xcode blob, docker volumes, SCAN=1)

test_storage_plan_drops_developer_blob() {
    setup_env storage-plan-dev-blob
    command rm -f "${TEST_BIN}/brew"
    local empty_root="${TEST_ROOT}/empty-dev"
    mkdir -p "$empty_root" "${TEST_HOME}/Library/Developer"
    local out="${TEST_ROOT}/storage-plan-dev-blob.out"

    run_freshen "$out" --storage-plan --dev-prune-root="$empty_root" --no-color
    assert_status 0 $? "Developer blob plan exits 0"
    assert_not_contains "$out" "report-only  ${TEST_HOME}/Library/Developer" "blob is not report-only"
    assert_not_contains "$out" "cache-prune  ${TEST_HOME}/Library/Developer" "blob is not cache-prune"
    assert_not_contains "$out" "review  ${TEST_HOME}/Library/Developer" "blob is not review"
}

test_storage_plan_docker_volumes_are_do_not_touch() {
    setup_env storage-plan-docker-vol
    command rm -f "${TEST_BIN}/brew"
    local empty_root="${TEST_ROOT}/empty-dev"
    mkdir -p "$empty_root" "${TEST_HOME}/.docker/volumes"
    local out="${TEST_ROOT}/storage-plan-docker-vol.out"

    run_freshen "$out" --storage-plan --dev-prune-root="$empty_root" --no-color
    assert_status 0 $? "docker volumes plan exits 0"
    assert_contains "$out" "report-only  ${TEST_HOME}/.docker/volumes" "docker volumes row is report-only"
    assert_contains "$out" "docker-volumes" "docker volumes labeled docker-volumes"
    assert_contains "$out" "do-not-touch" "docker volumes labeled do-not-touch"
    if grep -E "^[[:space:]]*review[[:space:]]+${TEST_HOME}/.docker$" "$out" >/dev/null 2>&1; then
        fail "parent .docker is not a review row"
    else
        pass "parent .docker is not a review row"
    fi
}

test_storage_plan_scan_surfaces_keeps_classes() {
    setup_env storage-plan-scan
    command rm -f "${TEST_BIN}/brew"
    export FRESHEN_STORAGE_SCAN_SURFACES=1
    local empty_root="${TEST_ROOT}/empty-dev"
    mkdir -p "$empty_root" "${TEST_HOME}/Library/Caches"
    local out="${TEST_ROOT}/storage-plan-scan.out"

    run_freshen "$out" --storage-plan --dev-prune-root="$empty_root" --no-color
    assert_status 0 $? "SCAN=1 plan exits 0"
    assert_contains "$out" "cache-prune" "SCAN=1 still prints cache-prune"
    assert_contains "$out" "restore:" "SCAN=1 still prints restore hints"
    assert_contains "$out" "${TEST_HOME}/Library/Caches" "SCAN=1 still lists Caches"
}
