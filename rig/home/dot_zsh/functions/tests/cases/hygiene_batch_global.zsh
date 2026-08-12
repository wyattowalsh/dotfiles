# Case pack: F2 _batch_status must not remain global

test_batch_status_not_global_after_upgrade() {
    setup_env hygiene-batch-global
    export BREW_OUTDATED_FORMULAE='foo'
    export BREW_FORMULA_UPGRADE_OUTPUT=$'==> Upgrading foo\nfoo 1.0 -> 1.1'
    local out="${TEST_ROOT}/hygiene-batch-global.out"
    run_freshen_hygiene_probe "$out" --yes --no-mas --no-cleanup --no-cache --no-color --progress=plain
    assert_not_contains "$out" "LEAK _batch_status" "batch status map is not left global"
    assert_not_contains "$out" "LEAK " "helpers do not leak after batch upgrade path"
}
