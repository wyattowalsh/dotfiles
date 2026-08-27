# Case pack: 1.10.0 storage reclaim policy (age skip, live workspace, classified plan)

_run_freshen_in() {
    local cwd="$1"
    local output_file="$2"
    shift 2
    local rc=0
    (
        cd -- "$cwd" || exit 2
        PATH="${TEST_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
        HOME="${TEST_HOME}" \
        XDG_STATE_HOME="${TEST_STATE}" \
        TMPDIR="${TEST_TMP}" \
        TRACE_FILE="${TRACE_FILE}" \
        zsh -fc 'fpath=("$1" $fpath); autoload -Uz freshen; shift; freshen "$@"' zsh "$FRESHEN_DIR" "$@"
    ) >"$output_file" 2>&1 || rc=$?
    return "$rc"
}

test_dev_prune_skips_fresh_node_modules() {
    setup_env dev-prune-fresh
    write_gomi_stub
    local project_root="${TEST_ROOT}/project"
    local modules_dir="${project_root}/node_modules"
    mkdir -p "$modules_dir"
    local out="${TEST_ROOT}/dev-prune-fresh.out"

    run_freshen "$out" --clean-only --yes --no-cleanup --dev-prune --dev-prune-root="$project_root" --progress=plain --no-color
    assert_status 0 $? "fresh cache skip still exits cleanly"
    assert_contains "$out" "skipped-recent: 1" "fresh cache is reported as skipped-recent: 1"
    assert_not_contains "$TRACE_FILE" "gomi -- ${modules_dir}" "fresh cache is not passed to gomi"
}

test_dev_prune_min_age_zero_allows_fresh() {
    setup_env dev-prune-age-zero
    write_gomi_stub
    export FRESHEN_DEV_PRUNE_MIN_AGE_DAYS=0
    local project_root="${TEST_ROOT}/project"
    local modules_dir="${project_root}/node_modules"
    mkdir -p "$modules_dir"
    local out="${TEST_ROOT}/dev-prune-age-zero.out"

    run_freshen "$out" --clean-only --yes --no-cleanup --dev-prune --dev-prune-root="$project_root" --progress=plain --no-color
    assert_status 0 $? "MIN_AGE_DAYS=0 execution exits cleanly"
    assert_contains "$TRACE_FILE" "gomi -- ${modules_dir}" "MIN_AGE_DAYS=0 still trashes a fresh matching cache"
}

test_dev_prune_skips_cwd_live_workspace() {
    setup_env dev-prune-live-cwd
    write_gomi_stub
    local project_root="${TEST_ROOT}/project"
    local modules_dir="${project_root}/node_modules"
    mkdir -p "$modules_dir"
    freshen_stamp_mtime_days_ago "$modules_dir" 20
    local out="${TEST_ROOT}/dev-prune-live-cwd.out"

    _run_freshen_in "$modules_dir" "$out" --clean-only --yes --no-cleanup --dev-prune --dev-prune-root="$project_root" --progress=plain --no-color
    assert_status 0 $? "live-workspace skip exits cleanly"
    assert_contains "$out" "skipped-live: 1" "cwd cache is reported as skipped-live: 1"
    assert_not_contains "$TRACE_FILE" "gomi -- ${modules_dir}" "cwd cache is not passed to gomi"
}

test_dev_prune_root_cwd_scans_descendants() {
    setup_env dev-prune-root-cwd
    write_gomi_stub
    local prune_root="${TEST_ROOT}/workspace"
    local modules_dir="${prune_root}/proj/node_modules"
    mkdir -p "$modules_dir"
    freshen_stamp_mtime_days_ago "$modules_dir" 20
    local out="${TEST_ROOT}/dev-prune-root-cwd.out"

    _run_freshen_in "$prune_root" "$out" --clean-only --yes --no-cleanup --dev-prune --dev-prune-root="$prune_root" --progress=plain --no-color
    assert_status 0 $? "prune-root cwd execution exits cleanly"
    assert_contains "$TRACE_FILE" "gomi -- ${modules_dir}" "cwd equal to prune root still trashes descendant caches"
}

test_storage_plan_labels_without_sizing() {
    setup_env storage-plan-labels
    command rm -f "${TEST_BIN}/brew"
    local empty_root="${TEST_ROOT}/empty-dev"
    mkdir -p "$empty_root" "${TEST_HOME}/Library/Caches" "${TEST_HOME}/Downloads"
    local out="${TEST_ROOT}/storage-plan-labels.out"

    run_freshen "$out" --storage-plan --dev-prune-root="$empty_root" --no-color
    assert_status 0 $? "classified storage-plan exits 0 without brew"
    assert_contains "$out" "cache-prune  ${TEST_HOME}/Library/Caches" "Caches row is cache-prune without sizing"
    assert_contains "$out" "restore:" "classified rows include restore hints"
    assert_contains "$out" "Skipped broad surface sizing" "storage-plan skips du by default"
    assert_contains "$out" "review  ${TEST_HOME}/Downloads" "Downloads row is review"
    assert_not_contains "$TRACE_FILE" "brew " "classified storage-plan does not invoke brew"
    assert_not_contains "$TRACE_FILE" "gomi --" "classified storage-plan does not call gomi"
    assert_not_contains "$TRACE_FILE" "docker system prune" "classified storage-plan does not docker prune"
}

test_storage_plan_unique_model_is_report_only() {
    setup_env storage-plan-lmstudio
    command rm -f "${TEST_BIN}/brew"
    local empty_root="${TEST_ROOT}/empty-dev"
    mkdir -p "$empty_root" "${TEST_HOME}/Library/Application Support/LM Studio"
    local out="${TEST_ROOT}/storage-plan-lmstudio.out"

    run_freshen "$out" --storage-plan --dev-prune-root="$empty_root" --no-color
    assert_status 0 $? "LM Studio row still leaves storage-plan at 0"
    assert_contains "$out" "report-only  ${TEST_HOME}/Library/Application Support/LM Studio" "LM Studio row is report-only"
    assert_contains "$out" "unique-model" "LM Studio is labeled unique-model"
    assert_contains "$out" "do-not-touch" "LM Studio is labeled do-not-touch"
    assert_not_contains "$TRACE_FILE" "gomi -- ${TEST_HOME}/Library/Application Support/LM Studio" "LM Studio is not passed to gomi"
}

test_storage_plan_kopia_missing_is_not_installed() {
    setup_env storage-plan-kopia-missing
    command rm -f "${TEST_BIN}/brew" "${TEST_BIN}/kopia"
    local empty_root="${TEST_ROOT}/empty-dev"
    mkdir -p "$empty_root"
    local out="${TEST_ROOT}/storage-plan-kopia-missing.out"

    run_freshen "$out" --storage-plan --dev-prune-root="$empty_root" --no-color
    assert_status 0 $? "missing Kopia does not fail storage-plan"
    assert_contains "$out" "not installed" "missing Kopia is reported as not installed"
    assert_contains "$out" "not recommended until Kopia verify succeeds" "missing Kopia does not recommend unique-cold reclaim"
}

test_storage_plan_kopia_status_fail_is_verify_unknown() {
    setup_env storage-plan-kopia-fail
    command rm -f "${TEST_BIN}/brew"
    write_tool_stub kopia
    export STUB_RC_KOPIA=1
    local empty_root="${TEST_ROOT}/empty-dev"
    mkdir -p "$empty_root"
    local out="${TEST_ROOT}/storage-plan-kopia-fail.out"

    run_freshen "$out" --storage-plan --dev-prune-root="$empty_root" --no-color
    assert_status 0 $? "failed Kopia status does not fail storage-plan"
    assert_contains "$out" "verify-unknown" "failed Kopia status is verify-unknown"
    assert_contains "$TRACE_FILE" "kopia repository status" "Kopia probe is repository status"
    assert_not_contains "$TRACE_FILE" "--password" "Kopia probe does not pass --password"
    assert_not_contains "$TRACE_FILE" " -p " "Kopia probe does not pass -p"
    assert_contains "$out" "not recommended until Kopia verify succeeds" "failed Kopia does not recommend unique-cold reclaim"
}

test_storage_plan_kopia_reachable_omits_unique_cold_block() {
    setup_env storage-plan-kopia-ok
    command rm -f "${TEST_BIN}/brew"
    write_tool_stub kopia
    export STUB_RC_KOPIA=0
    local empty_root="${TEST_ROOT}/empty-dev"
    mkdir -p "$empty_root"
    local out="${TEST_ROOT}/storage-plan-kopia-ok.out"

    run_freshen "$out" --storage-plan --dev-prune-root="$empty_root" --no-color
    assert_status 0 $? "reachable Kopia still leaves storage-plan at 0"
    assert_contains "$out" "Kopia: reachable" "reachable Kopia is reported"
    assert_not_contains "$out" "not recommended until Kopia verify succeeds" "reachable Kopia omits unique-cold block"
}

test_storage_plan_mentions_mo_not_invoked() {
    setup_env storage-plan-mo
    command rm -f "${TEST_BIN}/brew"
    write_tool_stub mo
    local empty_root="${TEST_ROOT}/empty-dev"
    mkdir -p "$empty_root"
    local out="${TEST_ROOT}/storage-plan-mo.out"

    run_freshen "$out" --storage-plan --dev-prune-root="$empty_root" --no-color
    assert_status 0 $? "Mole mention still leaves storage-plan at 0"
    assert_contains "$out" "mo clean -n" "Next Actions mention mo clean -n when mo exists"
    assert_contains "$out" "files-buddy" "Next Actions mention files-buddy offload/dedupe"
    assert_not_contains "$TRACE_FILE" "mo " "storage-plan does not invoke mo"
    assert_not_contains "$TRACE_FILE" "fb.py" "storage-plan does not invoke files-buddy"
}

test_storage_plan_docker_df_not_prune() {
    setup_env storage-plan-docker-df
    command rm -f "${TEST_BIN}/brew"
    export STUB_DOCKER_INFO_RC=0
    local empty_root="${TEST_ROOT}/empty-dev"
    mkdir -p "$empty_root"
    local out="${TEST_ROOT}/storage-plan-docker-df.out"

    run_freshen "$out" --storage-plan --dev-prune-root="$empty_root" --no-color
    assert_status 0 $? "docker df probe leaves storage-plan at 0"
    assert_contains "$TRACE_FILE" "docker system df" "storage-plan may run docker system df"
    assert_not_contains "$TRACE_FILE" "docker system prune" "storage-plan does not run docker system prune"
}

test_storage_plan_nix_gc_is_dry_run() {
    setup_env storage-plan-nix
    command rm -f "${TEST_BIN}/brew"
    write_tool_stub nix
    local empty_root="${TEST_ROOT}/empty-dev"
    mkdir -p "$empty_root"
    local out="${TEST_ROOT}/storage-plan-nix.out"

    run_freshen "$out" --storage-plan --dev-prune-root="$empty_root" --no-color
    assert_status 0 $? "nix dry-run probe leaves storage-plan at 0"
    assert_contains "$TRACE_FILE" "nix store gc --dry-run" "storage-plan nix probe is dry-run"
}

test_help_documents_dev_prune_min_age_days() {
    setup_env help-min-age
    local out="${TEST_ROOT}/help-min-age.out"
    run_freshen "$out" --help --no-color
    assert_status 0 $? "help still exits cleanly"
    assert_contains "$out" "FRESHEN_DEV_PRUNE_MIN_AGE_DAYS" "help documents FRESHEN_DEV_PRUNE_MIN_AGE_DAYS"
    assert_contains "$out" "FRESHEN_BACKUP_STATUS_TIMEOUT_SEC" "help documents FRESHEN_BACKUP_STATUS_TIMEOUT_SEC"
    assert_contains "$out" "SAFETY MODEL" "help still has SAFETY MODEL"
}

test_dev_prune_caps_huge_min_age_days() {
    setup_env dev-prune-huge-age
    write_gomi_stub
    export FRESHEN_DEV_PRUNE_MIN_AGE_DAYS=106751991167301
    local project_root="${TEST_ROOT}/project"
    local modules_dir="${project_root}/node_modules"
    mkdir -p "$modules_dir"
    local out="${TEST_ROOT}/dev-prune-huge-age.out"

    run_freshen "$out" --clean-only --yes --no-cleanup --dev-prune --dev-prune-root="$project_root" --progress=plain --no-color
    assert_status 0 $? "huge MIN_AGE_DAYS still exits cleanly"
    assert_not_contains "$TRACE_FILE" "gomi -- ${modules_dir}" "overflow min-age does not disable the age skip"
}
