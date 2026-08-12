# Case pack: F3 brew update timeout

test_brew_update_respects_short_timeout() {
    setup_env timeouts-update
    export BREW_UPDATE_SLEEP=5
    export FRESHEN_UPDATE_TIMEOUT_SEC=1
    local out="${TEST_ROOT}/timeouts-update.out"
    local started=$EPOCHSECONDS
    run_freshen "$out" --dry-run --yes --no-mas --no-cache --no-cleanup --progress=plain --no-color
    local rc=$?
    local elapsed=$(( EPOCHSECONDS - started ))
    # Should not wait full 5s sleep; timeout path should finish sooner
    if (( elapsed < 4 )); then
        pass "brew update short timeout returns before stub sleep completes"
    else
        fail "brew update short timeout returns before stub sleep completes"
    fi
    # Degraded or non-zero is acceptable; hang is not
    assert_contains "$out" "Inventory" "update timeout path still reports inventory phase"
    (( rc == 0 || rc == 1 )) && pass "update timeout path exits 0 or 1" || assert_status 1 "$rc" "update timeout path exits 0 or 1"
}

test_invalid_update_timeout_warns_and_falls_back() {
    setup_env timeouts-update-invalid
    export FRESHEN_UPDATE_TIMEOUT_SEC=not-a-number
    local out="${TEST_ROOT}/timeouts-update-invalid.out"
    run_freshen "$out" --clean-only --yes --no-cleanup --no-cache --progress=plain --no-color
    assert_status 0 $? "invalid update timeout does not abort clean-only"
    assert_contains "$out" "FRESHEN_UPDATE_TIMEOUT_SEC must be a non-negative integer; using 300" "invalid update timeout warning is actionable"
}
