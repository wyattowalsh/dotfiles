# Case pack: 1.13.0 storage-plan audit signals (named leaves, coverage, in-use)

_audit_kopia_json() {
    local music_files="${1:-10}" music_size="${2:-100}"
    local rel files size first=1
    print -n '['
    for rel in Documents Movies Music Pictures Public dev src .bash_profile .bashrc .codex/memories .gitconfig .github .gitignore .zshrc; do
        files=10
        size=100
        if [[ "$rel" == Music ]]; then
            files="$music_files"
            size="$music_size"
        fi
        (( first )) || print -n ','
        first=0
        print -n "{\"source\":{\"path\":\"${TEST_HOME}/${rel}\"},\"startTime\":\"2026-09-01T00:00:00Z\",\"stats\":{\"fileCount\":${files},\"totalSize\":${size}}}"
    done
    print ']'
}

_audit_storage_plan() {
    local out="$1"
    shift
    local empty_root="${TEST_ROOT}/empty-dev"
    mkdir -p "$empty_root"
    command rm -f "${TEST_BIN}/brew"
    [[ -n "$TEST_PYTHON3" ]] && ln -sf "$TEST_PYTHON3" "${TEST_BIN}/python3"
    : ${FRESHEN_KOPIA_NIGHTLY_RUNNING:=0}
    export FRESHEN_KOPIA_NIGHTLY_RUNNING
    run_freshen "$out" --storage-plan --dev-prune-root="$empty_root" --no-color "$@"
}

test_help_environment_lists_skip_casks() {
    setup_env help-skip-casks-env
    local out="${TEST_ROOT}/help-skip-casks.out"
    run_freshen "$out" --help
    assert_status 0 $? "help exits 0"
    assert_contains "$out" "FRESHEN_SKIP_CASKS" "help ENVIRONMENT lists FRESHEN_SKIP_CASKS"
    assert_contains "$out" "skip-casks" "help mentions skip-casks"
}

test_storage_plan_absent_named_leaves() {
    setup_env storage-absent-leaves
    local out="${TEST_ROOT}/storage-absent.out"
    _audit_storage_plan "$out"
    assert_status 0 $? "storage-plan with absent leaves exits 0"
    assert_contains "$out" "cache-prune  absent  ${TEST_HOME}/.cache/uv" "missing uv leaf is absent"
    assert_contains "$out" "cache-prune  absent  ${TEST_HOME}/.npm/_npx" "missing npm npx leaf is absent"
    assert_contains "$out" "cache-prune  absent  ${TEST_HOME}/Library/pnpm/store/v11" "missing pnpm v11 store is absent"
    assert_contains "$out" "review  absent  ${TEST_HOME}/.cache/opencode" "missing OpenCode leaf is absent"
    assert_contains "$out" "report-only  absent  ${TEST_HOME}/Library/CloudStorage" "missing CloudStorage is absent"
}

test_storage_plan_opencode_does_not_recommend_uninstall() {
    setup_env storage-opencode
    mkdir -p "${TEST_HOME}/.cache/opencode"
    local out="${TEST_ROOT}/storage-opencode.out"
    _audit_storage_plan "$out"
    assert_status 0 $? "OpenCode storage-plan exits 0"
    assert_contains "$out" "do not uninstall OpenCode" "OpenCode restore hint forbids uninstall"
}

test_storage_plan_cloudstorage_never_du() {
    setup_env storage-cloudstorage
    mkdir -p "${TEST_HOME}/Library/CloudStorage"
    write_tool_stub du
    export FRESHEN_STORAGE_SCAN_SURFACES=1
    local out="${TEST_ROOT}/storage-cloudstorage.out"
    _audit_storage_plan "$out"
    assert_status 0 $? "CloudStorage storage-plan exits 0"
    assert_contains "$out" "report-only  ${TEST_HOME}/Library/CloudStorage" "CloudStorage is listed without a size"
    assert_not_contains "$TRACE_FILE" "CloudStorage" "du is not invoked on CloudStorage"
}

test_storage_plan_parent_cache_not_sized() {
    setup_env storage-parent-cache
    mkdir -p "${TEST_HOME}/Library/Caches" "${TEST_HOME}/.cache"
    write_tool_stub du
    export FRESHEN_STORAGE_SCAN_SURFACES=1
    local out="${TEST_ROOT}/storage-parent-cache.out"
    _audit_storage_plan "$out"
    assert_status 0 $? "parent cache storage-plan exits 0"
    assert_contains "$out" "cache-prune  ${TEST_HOME}/Library/Caches" "user Caches is listed"
    assert_contains "$out" "cache-prune  ${TEST_HOME}/.cache" "user .cache is listed"
    assert_not_contains "$TRACE_FILE" "${TEST_HOME}/Library/Caches" "du is not invoked on Library/Caches"
    if grep -Fxq -- "du -sk -- ${TEST_HOME}/.cache" "$TRACE_FILE"; then
        fail "du is not invoked on parent .cache"
    else
        pass "du is not invoked on parent .cache"
    fi
}

test_storage_plan_inuse_uv_skips_force() {
    setup_env storage-uv-inuse
    local uv_leaf="${TEST_HOME}/.cache/uv"
    mkdir -p "$uv_leaf"
    cat > "${TEST_BIN}/ps" <<EOF
#!/usr/bin/env zsh
print -r -- "ps \$*" >> "\${TRACE_FILE}"
print -r -- "  4242 uv prune ${uv_leaf}"
exit 0
EOF
    chmod +x "${TEST_BIN}/ps"
    write_tool_stub du
    export FRESHEN_STORAGE_SCAN_SURFACES=1
    local out="${TEST_ROOT}/storage-uv-inuse.out"
    _audit_storage_plan "$out"
    assert_status 0 $? "in-use uv storage-plan exits 0"
    assert_contains "$out" "in-use / skip" "in-use uv is marked skip"
    assert_contains "$out" "never --force" "in-use restore hint forbids --force"
    assert_not_contains "$TRACE_FILE" "${uv_leaf}" "du is not invoked on in-use uv"
}

test_storage_plan_downloads_never_covered() {
    setup_env storage-downloads-cover
    write_tool_stub kopia
    export STUB_STDOUT_KOPIA
    STUB_STDOUT_KOPIA="$(_audit_kopia_json 10 100)"
    STUB_STDOUT_KOPIA="${STUB_STDOUT_KOPIA%]},{\"source\":{\"path\":\"${TEST_HOME}/Downloads\"},\"startTime\":\"2026-09-01T00:00:00Z\",\"stats\":{\"fileCount\":9,\"totalSize\":99}}]"
    local out="${TEST_ROOT}/storage-downloads.out"
    _audit_storage_plan "$out"
    assert_status 0 $? "coverage storage-plan exits 0"
    assert_contains "$out" "Downloads:" "Downloads coverage row is printed"
    assert_contains "$out" "not covered" "Downloads is never treated as covered"
}

test_storage_plan_zero_music_blocks_unique_cold() {
    setup_env storage-music-zero
    write_tool_stub kopia
    export STUB_STDOUT_KOPIA
    STUB_STDOUT_KOPIA="$(_audit_kopia_json 0 0)"
    local out="${TEST_ROOT}/storage-music-zero.out"
    _audit_storage_plan "$out"
    assert_status 0 $? "incomplete Music coverage exits 0"
    assert_contains "$out" "Music  files=0 size=0  incomplete" "zero-file Music is incomplete"
    assert_contains "$out" "Unique-cold reclaim:" "unique-cold row is printed"
    assert_contains "$out" "not recommended until Kopia coverage is complete" "unique-cold stays closed"
}

test_storage_plan_complete_coverage_keeps_unique_models() {
    setup_env storage-coverage-complete
    write_tool_stub kopia
    export STUB_STDOUT_KOPIA
    STUB_STDOUT_KOPIA="$(_audit_kopia_json 10 100)"
    local out="${TEST_ROOT}/storage-coverage-complete.out"
    _audit_storage_plan "$out"
    assert_status 0 $? "complete coverage storage-plan exits 0"
    assert_contains "$out" "coverage complete; unique models stay report-only" "complete coverage does not unlock unique-model delete"
}

test_storage_plan_nightly_running_skips_snapshot_list() {
    setup_env storage-nightly-running
    write_tool_stub kopia
    export STUB_STDOUT_KOPIA='{"ok":true}'
    export FRESHEN_KOPIA_NIGHTLY_RUNNING=1
    local out="${TEST_ROOT}/storage-nightly.out"
    _audit_storage_plan "$out"
    assert_status 0 $? "nightly-running storage-plan exits 0"
    assert_contains "$out" "nightly running; coverage not probed" "nightly overlap skips snapshot list"
    assert_not_contains "$TRACE_FILE" "snapshot list" "kopia snapshot list is not invoked while nightly runs"
}

test_storage_plan_simctl_license_skip() {
    setup_env storage-simctl-license
    write_tool_stub xcrun
    export STUB_RC_XCRUN=1
    export STUB_STDOUT_XCRUN="You have not agreed to the Xcode license agreements"
    export FRESHEN_TEST_SIMCTL=1
    local out="${TEST_ROOT}/storage-simctl.out"
    _audit_storage_plan "$out"
    assert_status 0 $? "simctl license skip exits 0"
    if [[ "$(uname -s)" == Darwin ]]; then
        assert_contains "$out" "simctl skipped: Xcode license" "license error is non-fatal"
    fi
    assert_not_contains "$TRACE_FILE" "runtime delete" "simctl delete is not invoked"
}

test_storage_plan_footer_and_no_mole() {
    setup_env storage-footer
    write_tool_stub mo
    local out="${TEST_ROOT}/storage-footer.out"
    _audit_storage_plan "$out"
    assert_status 0 $? "storage-plan footer exits 0"
    assert_contains "$out" "tool claim ≠ allocated delta ≠ measured free" "claimed≠measured footer"
    assert_contains "$out" "does not empty trash, delete simulators, invoke mo" "footer forbids mo/simctl delete"
    assert_not_contains "$TRACE_FILE" "mo " "mo is never executed"
}
