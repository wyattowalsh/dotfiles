# Case pack: F1 namespace hygiene (same-process probe)

test_nested_helpers_do_not_leak_after_run() {
    setup_env hygiene-namespace
    local out="${TEST_ROOT}/hygiene-namespace.out"
    # Missing brew forces early failure after helpers are defined
    PATH="/usr/bin:/bin" \
    HOME="${TEST_HOME}" \
    XDG_STATE_HOME="${TEST_STATE}" \
    TMPDIR="${TEST_TMP}" \
    run_freshen_hygiene_probe "$out" --yes --no-color --progress=plain
    assert_not_contains "$out" "LEAK " "nested freshen helpers do not leak after run"
}
