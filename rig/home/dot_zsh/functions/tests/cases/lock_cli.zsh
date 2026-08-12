# Case pack: F7 lock + F9 CLI parse

test_lock_blocks_second_instance() {
    setup_env lock-block
    local lock_dir="${TEST_STATE}/freshen/freshen.lock.d"
    mkdir -p "$lock_dir"
    # Live holder: current test shell pid is alive
    print -r -- "$$" >| "${lock_dir}/pid"
    local out="${TEST_ROOT}/lock-block.out"
    run_freshen "$out" --clean-only --yes --no-cleanup --no-cache --progress=plain --no-color
    assert_status 1 $? "live lock blocks second freshen"
    assert_contains "$out" "another freshen is running" "lock conflict message is explicit"
}

test_lock_reclaims_stale_pid() {
    setup_env lock-stale
    local lock_dir="${TEST_STATE}/freshen/freshen.lock.d"
    mkdir -p "$lock_dir"
    print -r -- "999999" >| "${lock_dir}/pid"
    local out="${TEST_ROOT}/lock-stale.out"
    run_freshen "$out" --clean-only --yes --no-cleanup --no-cache --progress=plain --no-color
    assert_status 0 $? "stale lock is reclaimed"
}

test_version_does_not_leave_lock() {
    setup_env lock-version
    local out="${TEST_ROOT}/lock-version.out"
    run_freshen "$out" --version --no-color
    assert_status 0 $? "version exits cleanly without lock side effects"
    [[ ! -d "${TEST_STATE}/freshen/freshen.lock.d" ]] && pass "version does not create lock dir" || fail "version does not create lock dir"
}

test_progress_space_separated_value() {
    setup_env cli-progress-space
    local out="${TEST_ROOT}/cli-progress-space.out"
    run_freshen "$out" --dry-run --yes --no-mas --no-cache --no-cleanup --progress plain --no-color
    assert_status 0 $? "space-separated --progress plain is accepted"
}

test_unknown_positional_rejected() {
    setup_env cli-positional
    local out="${TEST_ROOT}/cli-positional.out"
    run_freshen "$out" --dry-run --yes EXTRA
    assert_status 2 $? "unknown positional is rejected"
    assert_contains "$out" "unexpected argument" "positional rejection message is explicit"
}

test_formula_and_cask_only_conflict() {
    setup_env cli-fk-conflict
    local out="${TEST_ROOT}/cli-fk-conflict.out"
    run_freshen "$out" --formula-only --cask-only --yes --no-color
    assert_status 2 $? "formula-only with cask-only is a usage error"
    assert_contains "$out" "mutually exclusive" "exclusive-mode message is explicit"
}
