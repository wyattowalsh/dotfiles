# Case pack: F5 mas success is not inflated "confirmed N"

test_mas_success_does_not_claim_confirmed_count() {
    setup_env mas-honesty
    export MAS_OUTDATED=$'111 OneApp\n222 TwoApp'
    export MAS_UPDATE_RC=0
    local out="${TEST_ROOT}/mas-honesty.out"
    run_freshen "$out" --yes --no-cache --no-cleanup --progress=plain --no-color
    local rc=$?
    (( rc == 0 || rc == 1 )) || assert_status 0 "$rc" "mas success path exits cleanly"
    assert_contains "$out" "mas exit 0" "mas success uses honest exit-0 wording"
    assert_not_contains "$out" "confirmed 2" "mas success does not claim confirmed count for all apps"
}
