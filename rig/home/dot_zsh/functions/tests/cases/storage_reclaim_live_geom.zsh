# Case pack: live-workspace geometry (cwd descendant / ancestor)

test_dev_prune_skips_descendant_of_cwd() {
    setup_env dev-prune-live-desc
    write_gomi_stub
    local prune_root="${TEST_ROOT}/workspace"
    local proj="${prune_root}/proj"
    local modules_dir="${proj}/node_modules"
    mkdir -p "$modules_dir"
    freshen_stamp_mtime_days_ago "$modules_dir" 20 || fail "stamp mtime 20d"
    local out="${TEST_ROOT}/dev-prune-live-desc.out"

    run_freshen_in "$proj" "$out" --clean-only --yes --no-cleanup --dev-prune --dev-prune-root="$prune_root" --progress=plain --no-color
    assert_status 0 $? "descendant-of-cwd skip exits cleanly"
    assert_contains "$out" "skipped-live: 1" "project cwd skips descendant node_modules as live"
    assert_not_contains "$TRACE_FILE" "gomi -- ${modules_dir}" "descendant cache is not passed to gomi"
}

test_dev_prune_skips_when_cwd_under_candidate() {
    setup_env dev-prune-live-under
    write_gomi_stub
    local prune_root="${TEST_ROOT}/workspace"
    local modules_dir="${prune_root}/proj/node_modules"
    local nested="${modules_dir}/pkg"
    mkdir -p "$nested"
    freshen_stamp_mtime_days_ago "$modules_dir" 20 || fail "stamp mtime 20d"
    local out="${TEST_ROOT}/dev-prune-live-under.out"

    run_freshen_in "$nested" "$out" --clean-only --yes --no-cleanup --dev-prune --dev-prune-root="$prune_root" --progress=plain --no-color
    assert_status 0 $? "cwd-under-candidate skip exits cleanly"
    assert_contains "$out" "skipped-live: 1" "cwd inside node_modules skips that cache"
    assert_not_contains "$TRACE_FILE" "gomi -- ${modules_dir}" "ancestor cache is not passed to gomi"
}
