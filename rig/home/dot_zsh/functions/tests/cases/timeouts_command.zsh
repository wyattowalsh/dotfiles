# Residual + inventory GNU timeout must use `command timeout`/`gtimeout`
# so a zshrc alias (timeout=gtimeout) is not expanded.

test_residual_inventory_timeout_uses_command_prefix() {
    setup_env timeout-command-prefix
    local bare="${TEST_ROOT}/bare-timeout.txt"
    : >| "$bare"
    # Invocations are `timeout "$sec"` / `gtimeout "$sec"` (not help prose).
    grep -nE '^[[:space:]]+(timeout|gtimeout)[[:space:]]+"' "$FRESHEN_FILE" >| "$bare" || true
    if [[ -s "$bare" ]]; then
        print -u2 -r -- "bare timeout/gtimeout invocations (need command prefix):"
        cat "$bare" >&2
        fail "residual/inventory timeout uses command timeout or gtimeout"
    else
        pass "residual/inventory timeout uses command timeout or gtimeout"
    fi
    assert_contains "$FRESHEN_FILE" "command timeout" "freshen invokes timeout via command"
}
