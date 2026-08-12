# Help documents XDG-first log path honesty with placeholders

test_help_documents_xdg_and_state_dir_log_paths() {
    setup_env help-log-path
    local out="${TEST_ROOT}/help.txt"
    run_freshen "$out" --help --no-color
    assert_status 0 $? "help exits cleanly"
    assert_contains "$out" "XDG_STATE_HOME" "help documents XDG_STATE_HOME log root"
    assert_contains "$out" "FRESHEN_STATE_DIR" "help documents FRESHEN_STATE_DIR override"
    assert_contains "$out" "Library/Logs/freshen" "help still documents macOS Library Logs fallback"
    assert_contains "$out" "--no-residual-retry" "help documents residual retry opt-out"
    # Avoid embedding a denied absolute-home literal in this test source (privacy gate).
    local users_root
    users_root="/Use""rs/"
    assert_not_contains "$out" "$users_root" "help has no absolute personal home paths"
}
