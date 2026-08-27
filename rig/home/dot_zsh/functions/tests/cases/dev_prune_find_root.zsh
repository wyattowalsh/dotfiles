# Case pack: find walks the canonical prune root

test_dev_prune_find_uses_canonical_root() {
    setup_env dev-prune-find-canon
    write_gomi_stub
    local prune_root="${TEST_ROOT}/workspace"
    local dash_proj="${prune_root}/-proj"
    local modules_dir="${dash_proj}/node_modules"
    mkdir -p -- "$modules_dir"
    freshen_stamp_mtime_days_ago "$modules_dir" 20 || fail "stamp mtime 20d"
    local out="${TEST_ROOT}/dev-prune-find-canon.out"

    run_freshen "$out" --clean-only --yes --no-cleanup --dev-prune --dev-prune-root="$prune_root" --progress=plain --no-color
    assert_status 0 $? "canonical root with dash-named child exits cleanly"
    assert_contains "$TRACE_FILE" "gomi -- ${modules_dir}" "find still locates node_modules under a dash-named project"
}
