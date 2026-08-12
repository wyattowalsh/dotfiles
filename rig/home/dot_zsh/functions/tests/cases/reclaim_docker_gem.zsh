# Case pack: F4 docker/gem reclaim is opt-in

test_default_cache_skips_docker_and_gem() {
    setup_env reclaim-default
    local out="${TEST_ROOT}/reclaim-default.out"
    run_freshen "$out" --clean-only --yes --no-cleanup --progress=plain --no-color
    assert_status 0 $? "default clean-only cache path succeeds"
    assert_not_contains "$TRACE_FILE" "docker system prune" "default path does not docker prune"
    assert_not_contains "$TRACE_FILE" "gem cleanup" "default path does not gem cleanup"
}

test_docker_prune_opt_in() {
    setup_env reclaim-docker
    export STUB_DOCKER_INFO_RC=0
    local out="${TEST_ROOT}/reclaim-docker.out"
    run_freshen "$out" --clean-only --yes --no-cleanup --docker-prune --progress=plain --no-color
    assert_status 0 $? "docker prune opt-in succeeds"
    assert_contains "$TRACE_FILE" "docker system prune -f" "docker prune opt-in traces prune"
}

test_gem_cleanup_opt_in() {
    setup_env reclaim-gem
    local out="${TEST_ROOT}/reclaim-gem.out"
    run_freshen "$out" --clean-only --yes --no-cleanup --gem-cleanup --progress=plain --no-color
    assert_status 0 $? "gem cleanup opt-in succeeds"
    assert_contains "$TRACE_FILE" "gem cleanup" "gem cleanup opt-in traces cleanup"
}
