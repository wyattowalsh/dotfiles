# Skip casks whose live app is already newer than the tap version.

write_app_plist() {
    local app_path="$1" short="$2" bundle="${3:-}"
    mkdir -p "${app_path}/Contents"
    {
        print '<?xml version="1.0" encoding="UTF-8"?>'
        print '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        print '<plist version="1.0">'
        print '<dict>'
        print '  <key>CFBundleShortVersionString</key>'
        print "  <string>${short}</string>"
        if [[ -n "$bundle" ]]; then
            print '  <key>CFBundleVersion</key>'
            print "  <string>${bundle}</string>"
        fi
        print '</dict>'
        print '</plist>'
    } >| "${app_path}/Contents/Info.plist"
}

cask_info_json_one() {
    local token="$1" version="$2" target="$3" app="${4:-${target:t}}"
    print -r -- "{\"casks\":[{\"token\":\"${token}\",\"version\":\"${version}\",\"installed\":\"${version}\",\"artifacts\":[{\"app\":[\"${app}\"],\"target\":\"${target}\"}]}]}"
}

test_help_documents_cask_skip_newer() {
    setup_env help-cask-skip-newer
    local out="${TEST_ROOT}/help.out"
    run_freshen "$out" --help --no-color
    assert_status 0 $? "help still exits cleanly"
    assert_contains "$out" "already newer" "help documents skip of live-newer casks"
}

test_cask_skips_live_newer_than_brew() {
    setup_env cask-skip-live-newer
    local app="${TEST_HOME}/Applications/BetterDisplay.app"
    write_app_plist "$app" "5.0.3"
    export BREW_OUTDATED_FORMULAE=""
    export BREW_OUTDATED_CASKS='betterdisplay'
    export BREW_CASK_INFO_JSON="$(cask_info_json_one betterdisplay 4.3.6 "$app")"
    export BREW_CASK_SINGLE_OUTPUT_BETTERDISPLAY=$'==> Upgrading Cask betterdisplay\nbetterdisplay: 4.3.6 -> 4.3.6'
    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --no-sudo-preflight --progress=plain --no-color
    assert_status 0 $? "live-newer cask skip exits 0"
    assert_contains "$out" "Skipped (already newer)" "prints skip heading"
    assert_contains "$out" "betterdisplay (5.0.3 > 4.3.6)" "prints live vs proposed versions"
    assert_not_contains "$TRACE_FILE" "brew upgrade" "does not reinstall a live-newer cask"
}

test_cask_upgrades_when_live_older() {
    setup_env cask-upgrade-live-older
    local app="${TEST_HOME}/Applications/Firefox.app"
    write_app_plist "$app" "1.0"
    export BREW_OUTDATED_FORMULAE=""
    export BREW_OUTDATED_CASKS='firefox'
    export BREW_CASK_INFO_JSON="$(cask_info_json_one firefox 1.1 "$app")"
    export BREW_CASK_SINGLE_OUTPUT_FIREFOX=$'==> Upgrading Cask firefox\nfirefox: 1.0 -> 1.1'
    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --no-sudo-preflight --progress=plain --no-color
    assert_status 0 $? "live-older cask upgrade exits 0"
    assert_contains "$TRACE_FILE" "brew upgrade --cask --greedy firefox" "upgrades when live is older"
    assert_not_contains "$out" "Skipped (already newer)" "does not claim a skip when live is older"
}

test_cask_equal_versions_still_upgrade() {
    setup_env cask-equal-still-upgrade
    local app="${TEST_HOME}/Applications/Discord.app"
    write_app_plist "$app" "1.1"
    export BREW_OUTDATED_FORMULAE=""
    export BREW_OUTDATED_CASKS='discord'
    export BREW_CASK_INFO_JSON="$(cask_info_json_one discord 1.1 "$app")"
    export BREW_CASK_SINGLE_OUTPUT_DISCORD=$'==> Upgrading Cask discord\ndiscord: 1.1 -> 1.1'
    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --no-sudo-preflight --progress=plain --no-color
    assert_status 0 $? "equal-version greedy upgrade exits 0"
    assert_contains "$TRACE_FILE" "brew upgrade --cask --greedy discord" "equal live vs tap still upgrades"
}

test_cask_skip_newer_mixed_list() {
    setup_env cask-skip-mixed
    local bd="${TEST_HOME}/Applications/BetterDisplay.app"
    local ff="${TEST_HOME}/Applications/Firefox.app"
    write_app_plist "$bd" "5.0.3"
    write_app_plist "$ff" "1.0"
    export BREW_OUTDATED_FORMULAE=""
    export BREW_OUTDATED_CASKS=$'betterdisplay\nfirefox'
    export BREW_CASK_INFO_JSON="{\"casks\":[{\"token\":\"betterdisplay\",\"version\":\"4.3.6\",\"installed\":\"4.3.6\",\"artifacts\":[{\"app\":[\"BetterDisplay.app\"],\"target\":\"${bd}\"}]},{\"token\":\"firefox\",\"version\":\"1.1\",\"installed\":\"1.0\",\"artifacts\":[{\"app\":[\"Firefox.app\"],\"target\":\"${ff}\"}]}]}"
    export BREW_CASK_SINGLE_OUTPUT_FIREFOX=$'==> Upgrading Cask firefox\nfirefox: 1.0 -> 1.1'
    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --no-sudo-preflight --progress=plain --no-color
    assert_status 0 $? "mixed skip/upgrade exits 0"
    assert_contains "$out" "betterdisplay (5.0.3 > 4.3.6)" "mixed list reports skipped cask"
    assert_contains "$TRACE_FILE" "brew upgrade --cask --greedy firefox" "mixed list upgrades the older cask"
    assert_not_contains "$TRACE_FILE" "brew upgrade --cask --greedy betterdisplay" "mixed list does not upgrade the newer cask"
    assert_not_contains "$TRACE_FILE" "brew upgrade --cask --greedy betterdisplay firefox" "mixed list does not batch-upgrade the skipped cask"
}

test_cask_info_miss_fail_open() {
    setup_env cask-info-miss-fail-open
    export BREW_OUTDATED_FORMULAE=""
    export BREW_OUTDATED_CASKS='firefox'
    unset BREW_CASK_INFO_JSON
    export BREW_CASK_SINGLE_OUTPUT_FIREFOX=$'==> Upgrading Cask firefox\nfirefox: 1.0 -> 1.1'
    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --no-sudo-preflight --progress=plain --no-color
    assert_status 0 $? "missing cask info still upgrades"
    assert_contains "$TRACE_FILE" "brew upgrade --cask --greedy firefox" "fail-open keeps the upgrade when info is empty"
}

test_cask_skip_newer_dry_run() {
    setup_env cask-skip-newer-dry-run
    local app="${TEST_HOME}/Applications/BetterDisplay.app"
    write_app_plist "$app" "5.0.3"
    export BREW_OUTDATED_FORMULAE=""
    export BREW_OUTDATED_CASKS='betterdisplay'
    export BREW_CASK_INFO_JSON="$(cask_info_json_one betterdisplay 4.3.6 "$app")"
    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --dry-run --cask-only --no-mas --no-cleanup --no-cache --progress=plain --no-color
    assert_status 0 $? "dry-run skip-newer exits 0"
    assert_contains "$out" "Skipped (already newer)" "dry-run reports skip"
    assert_contains "$out" "betterdisplay (5.0.3 > 4.3.6)" "dry-run shows live vs proposed"
    assert_not_contains "$TRACE_FILE" "brew upgrade" "dry-run does not upgrade skipped cask"
}

test_cask_plus_vs_comma_not_skip() {
    setup_env cask-plus-comma-equal
    local app="${TEST_HOME}/Applications/LM Studio.app"
    write_app_plist "$app" "0.4.21+2"
    export BREW_OUTDATED_FORMULAE=""
    export BREW_OUTDATED_CASKS='lm-studio'
    export BREW_CASK_INFO_JSON="$(cask_info_json_one lm-studio '0.4.21,2' "$app" 'LM Studio.app')"
    export BREW_CASK_SINGLE_OUTPUT_LM_STUDIO=$'==> Upgrading Cask lm-studio\nlm-studio: 0.4.21,2 -> 0.4.21,2'
    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --no-sudo-preflight --progress=plain --no-color
    assert_status 0 $? "delimiter-equal versions exit 0"
    assert_contains "$TRACE_FILE" "brew upgrade --cask --greedy lm-studio" "plus vs comma is not treated as newer"
    assert_not_contains "$out" "Skipped (already newer)" "plus vs comma does not skip"
}

test_cask_bundle_version_does_not_skip() {
    setup_env cask-bundle-version-trap
    local app="${TEST_HOME}/Applications/BetterDisplay.app"
    write_app_plist "$app" "4.3.6" "52922"
    export BREW_OUTDATED_FORMULAE=""
    export BREW_OUTDATED_CASKS='betterdisplay'
    export BREW_CASK_INFO_JSON="$(cask_info_json_one betterdisplay 4.3.6 "$app")"
    export BREW_CASK_SINGLE_OUTPUT_BETTERDISPLAY=$'==> Upgrading Cask betterdisplay\nbetterdisplay: 4.3.6 -> 4.3.6'
    local out="${TEST_ROOT}/out.txt"
    run_freshen "$out" --yes --cask-only --no-mas --no-cleanup --no-cache --no-sudo-preflight --progress=plain --no-color
    assert_status 0 $? "bundle-version trap exits 0"
    assert_contains "$TRACE_FILE" "brew upgrade --cask --greedy betterdisplay" "CFBundleVersion is not used for skip"
    assert_not_contains "$out" "Skipped (already newer)" "build number 52922 does not skip 4.3.6"
}

test_cask_skip_newer_python3_missing_keeps_inventory() {
    setup_env cask-skip-python-missing
    local app="${TEST_HOME}/Applications/BetterDisplay.app"
    write_app_plist "$app" "5.0.3"
    export BREW_OUTDATED_FORMULAE=""
    export BREW_OUTDATED_CASKS='betterdisplay'
    export BREW_CASK_INFO_JSON="$(cask_info_json_one betterdisplay 4.3.6 "$app")"
    command rm -f "${TEST_BIN}/python3"
    local cmd
    for cmd in find awk sed sort mktemp uname stat; do
        [[ -x "/usr/bin/${cmd}" ]] && ln -sfn "/usr/bin/${cmd}" "${TEST_BIN}/${cmd}"
    done
    local out="${TEST_ROOT}/out.txt"
    local rc=0
    PATH="${TEST_BIN}:/bin" \
    HOME="${TEST_HOME}" \
    XDG_STATE_HOME="${TEST_STATE}" \
    TMPDIR="${TEST_TMP}" \
    TRACE_FILE="${TRACE_FILE}" \
    zsh -fc 'fpath=("$1" $fpath); autoload -Uz freshen; shift; freshen "$@"' zsh "$FRESHEN_DIR" \
        --dry-run --cask-only --no-mas --no-cleanup --no-cache --progress=plain --no-color \
        >"$out" 2>&1 || rc=$?
    assert_status 0 "$rc" "missing python3 dry-run still exits 0"
    assert_contains "$out" "SKIP NEWER python3 missing" "missing python3 is logged"
    assert_not_contains "$out" "Skipped (already newer)" "missing python3 keeps inventory instead of skipping"
}
