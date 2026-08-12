# Case pack: F6 soft "failed" substring must not clobber upgraded

test_batch_failed_substring_does_not_clobber_upgraded() {
    setup_env classifier-clobber
    # Two packages exercise the batch upgrade path (BREW_FORMULA_UPGRADE_OUTPUT).
    export BREW_OUTDATED_FORMULAE=$'foo\nbar'
    export BREW_FORMULA_UPGRADE_RC=0
    export BREW_FORMULA_UPGRADE_OUTPUT=$'==> Upgrading foo\nfoo 1.0 -> 1.1\nfoo: something failed soft warning from caveats\n==> Upgrading bar\nbar 2.0 -> 2.1'
    local out="${TEST_ROOT}/classifier-clobber.out"
    run_freshen "$out" --yes --no-mas --no-cleanup --no-cache --progress=plain --no-color
    local rc=$?
    assert_contains "$out" "confirmed 2" "soft failed substring still counts upgraded packages"
    assert_not_contains "$out" "failed 1" "soft failed substring does not mark package failed"
    assert_not_contains "$out" "Formulae: degraded" "formula lane is not degraded by soft failed caveats"
    assert_status 0 "$rc" "soft failed substring does not degrade confirmed upgrade"
}
