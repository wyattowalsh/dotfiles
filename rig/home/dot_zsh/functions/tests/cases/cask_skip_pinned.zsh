# Skip casks listed in FRESHEN_SKIP_CASKS or ~/.config/freshen/skip-casks.

test_help_documents_cask_skip_pinned() {
    setup_env help-cask-skip-pinned
    local out="${TEST_ROOT}/help.out"
    run_freshen "$out" --help --no-color
    assert_status 0 $? "help still exits cleanly"
    assert_contains "$out" "skip-casks" "help documents pinned cask skip file"
    assert_contains "$out" "FRESHEN_SKIP_CASKS" "help documents FRESHEN_SKIP_CASKS"
}

test_cask_skips_pinned_via_env() {
    setup_env cask-skip-pinned-env
    export FRESHEN_SKIP_CASKS="spotify"
    export BREW_OUTDATED_FORMULAE=""
    export BREW_OUTDATED_CASKS=$'spotify\nfirefox'
    export BREW_CASK_INFO_JSON='{"casks":[]}'
    export BREW_CASK_SINGLE_OUTPUT_FIREFOX=$'==> Upgrading Cask firefox\nfirefox: 1.0 -> 1.1'
    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --no-sudo-preflight --progress=plain --no-color
    assert_status 0 $? "pinned cask skip exits 0"
    assert_contains "$out" "Skipped (pinned)" "prints pinned skip heading"
    assert_contains "$out" "spotify" "lists pinned token"
    assert_contains "$TRACE_FILE" "brew upgrade --cask --greedy firefox" "still upgrades unpinned casks"
    assert_not_contains "$TRACE_FILE" "brew upgrade --cask --greedy spotify" "does not upgrade pinned spotify"
}

test_cask_skips_pinned_via_config_file() {
    setup_env cask-skip-pinned-file
    export XDG_CONFIG_HOME="${TEST_ROOT}/config"
    mkdir -p "${XDG_CONFIG_HOME}/freshen"
    print -r -- $'# comment\nspotify\n' >| "${XDG_CONFIG_HOME}/freshen/skip-casks"
    export BREW_OUTDATED_FORMULAE=""
    export BREW_OUTDATED_CASKS='spotify'
    export BREW_CASK_INFO_JSON='{"casks":[]}'
    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --no-sudo-preflight --progress=plain --no-color
    assert_status 0 $? "config-file pinned skip exits 0"
    assert_contains "$out" "Skipped (pinned)" "prints pinned skip heading"
    assert_not_contains "$TRACE_FILE" "brew upgrade --cask" "does not upgrade when the only cask is pinned"
}

test_cask_skip_pinned_dry_run() {
    setup_env cask-skip-pinned-dry
    export FRESHEN_SKIP_CASKS="spotify"
    export BREW_OUTDATED_FORMULAE=""
    export BREW_OUTDATED_CASKS='spotify'
    export BREW_CASK_INFO_JSON='{"casks":[]}'
    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --dry-run --cask-only --no-mas --no-cleanup --no-cache --no-sudo-preflight --progress=plain --no-color
    assert_status 0 $? "dry-run pinned skip exits 0"
    assert_contains "$out" "Skipped (pinned)" "dry-run reports pinned skip"
    assert_not_contains "$TRACE_FILE" "brew upgrade" "dry-run does not upgrade skipped cask"
}
