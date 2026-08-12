# Case pack: every nested helper def appears in the static registry list

test_all_nested_helpers_are_registered() {
    setup_env hygiene-registry-meta
    local tmp="${TEST_ROOT}/registry-check.txt"
    local missing="${TEST_ROOT}/registry-missing.txt"
    : >| "$missing"

    # Nested defs are indented 4 spaces inside freshen()
    sed -n 's/^    \([A-Za-z_][A-Za-z0-9_]*\)() {/\1/p' "$FRESHEN_FILE" | sort -u >| "$tmp"

    local name
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        if ! grep -Eq "(^|[[:space:]])${name}([[:space:]]|\\)|$)" "$FRESHEN_FILE"; then
            print -r -- "$name" >> "$missing"
        fi
        # Must appear in _freshen_helper_fns assignment block
        if ! awk '/_freshen_helper_fns=\(/,/\)/' "$FRESHEN_FILE" | grep -Fq -- "$name"; then
            print -r -- "$name" >> "$missing"
        fi
    done < "$tmp"

    if [[ -s "$missing" ]]; then
        print -u2 -r -- "unregistered nested helpers:"
        cat "$missing" >&2
        fail "all nested helpers are listed in _freshen_helper_fns"
    else
        pass "all nested helpers are listed in _freshen_helper_fns"
    fi
}
