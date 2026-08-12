# Case pack: help documents new env/flags

test_help_documents_du_timeout_and_reclaim_and_update_timeout() {
    setup_env help-env-docs
    local out="${TEST_ROOT}/help-env-docs.out"
    run_freshen "$out" --help --no-color
    assert_status 0 $? "help still exits cleanly"
    assert_contains "$out" "FRESHEN_DU_TIMEOUT_SEC" "help documents FRESHEN_DU_TIMEOUT_SEC"
    assert_contains "$out" "FRESHEN_UPDATE_TIMEOUT_SEC" "help documents FRESHEN_UPDATE_TIMEOUT_SEC"
    assert_contains "$out" "FRESHEN_UPGRADE_TIMEOUT_SEC" "help documents FRESHEN_UPGRADE_TIMEOUT_SEC"
    assert_contains "$out" "FRESHEN_RESIDUAL_MAX" "help documents FRESHEN_RESIDUAL_MAX"
    assert_contains "$out" "FRESHEN_RESIDUAL_INVENTORY_TIMEOUT_SEC" "help documents FRESHEN_RESIDUAL_INVENTORY_TIMEOUT_SEC"
    assert_contains "$out" "--docker-prune" "help documents docker prune opt-in"
    assert_contains "$out" "--gem-cleanup" "help documents gem cleanup opt-in"
    assert_contains "$out" "OPTIONAL RECLAIM" "help separates optional reclaim from caches"
}
