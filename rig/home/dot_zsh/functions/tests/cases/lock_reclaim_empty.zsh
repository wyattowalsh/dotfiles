# Empty / non-numeric pid files are stale and must be reclaimed
# (numeric glob <-> is not required).

test_lock_reclaims_empty_pid() {
    setup_env lock-empty-pid
    local lock_dir="${TEST_STATE}/freshen/freshen.lock.d"
    mkdir -p "$lock_dir"
    : >| "${lock_dir}/pid"
    local out="${TEST_ROOT}/lock-empty-pid.out"
    run_freshen "$out" --clean-only --yes --no-cleanup --no-cache --progress=plain --no-color
    assert_status 0 $? "empty pid file is reclaimed as stale"
    assert_not_contains "$out" "another freshen is running" "empty pid does not report a live lock conflict"
}

test_lock_reclaims_non_numeric_pid() {
    setup_env lock-non-numeric-pid
    local lock_dir="${TEST_STATE}/freshen/freshen.lock.d"
    mkdir -p "$lock_dir"
    print -r -- "not-a-pid" >| "${lock_dir}/pid"
    local out="${TEST_ROOT}/lock-non-numeric-pid.out"
    run_freshen "$out" --clean-only --yes --no-cleanup --no-cache --progress=plain --no-color
    assert_status 0 $? "non-numeric pid file is reclaimed as stale"
    assert_not_contains "$out" "another freshen is running" "non-numeric pid does not report a live lock conflict"
}
