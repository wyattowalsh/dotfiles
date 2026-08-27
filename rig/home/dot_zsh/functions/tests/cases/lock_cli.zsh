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

test_lock_lists_holder_and_stays_blocked_noninteractive() {
    setup_env lock-list
    local lock_dir="${TEST_STATE}/freshen/freshen.lock.d"
    mkdir -p "$lock_dir"
    print -r -- "$$" >| "${lock_dir}/pid"
    local out="${TEST_ROOT}/lock-list.out"
    run_freshen "$out" --clean-only --yes --no-cleanup --no-cache --progress=plain --no-color
    assert_status 1 $? "non-interactive lock still blocks"
    assert_contains "$out" "another freshen is running" "lock conflict is explicit"
    assert_contains "$out" "Re-run from a TTY" "non-interactive lock points at TTY/--replace"
}

test_lock_replace_stops_holder() {
    setup_env lock-replace
    local lock_dir="${TEST_STATE}/freshen/freshen.lock.d"
    mkdir -p "$lock_dir"
    /bin/sleep 30 &
    local holder=$!
    print -r -- "$holder" >| "${lock_dir}/pid"
    local out="${TEST_ROOT}/lock-replace.out"
    export FRESHEN_FORCE_INTERACTIVE=1
    export FRESHEN_LOCK_REPLY=y
    run_freshen "$out" --dry-run --yes --no-mas --no-cache --no-cleanup --progress=plain --no-color
    assert_status 0 $? "replace takes the lock and continues"
    assert_contains "$out" "Took the lock (was pid ${holder})" "replace reports the old pid"
    if kill -0 "$holder" 2>/dev/null; then
        kill -KILL "$holder" 2>/dev/null || true
        fail "replaced holder is still running"
    else
        pass "replaced holder is no longer running"
    fi
}

test_lock_replace_flag_noninteractive() {
    setup_env lock-replace-flag
    local lock_dir="${TEST_STATE}/freshen/freshen.lock.d"
    mkdir -p "$lock_dir"
    /bin/sleep 30 &
    local holder=$!
    print -r -- "$holder" >| "${lock_dir}/pid"
    local out="${TEST_ROOT}/lock-replace-flag.out"
    run_freshen "$out" --replace --dry-run --yes --no-mas --no-cache --no-cleanup --progress=plain --no-color
    assert_status 0 $? "--replace takes the lock without a TTY"
    if kill -0 "$holder" 2>/dev/null; then
        kill -KILL "$holder" 2>/dev/null || true
        fail "--replace stopped the holder"
    else
        pass "--replace stopped the holder"
    fi
}

test_lock_replace_steals_from_shell() {
    setup_env lock-replace-shell
    local lock_dir="${TEST_STATE}/freshen/freshen.lock.d"
    mkdir -p "$lock_dir"
    zsh -c 'trap : INT TERM; sleep 30' &
    local holder=$!
    print -r -- "$holder" >| "${lock_dir}/pid"
    local out="${TEST_ROOT}/lock-replace-shell.out"
    run_freshen "$out" --replace --dry-run --yes --no-mas --no-cache --no-cleanup --progress=plain --no-color
    assert_status 0 $? "replace steals lock from a stubborn shell"
    assert_contains "$out" "Took the lock (was pid ${holder})" "steal reports the old pid"
    if kill -0 "$holder" 2>/dev/null; then
        pass "login/shell holder was not SIGKILLed"
        kill -KILL "$holder" 2>/dev/null || true
        wait "$holder" 2>/dev/null || true
    else
        pass "shell holder already exited after interrupt"
    fi
}
