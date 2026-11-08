#!/usr/bin/env bats
# Ghostty source contracts run against a disposable copy, never the live config.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/ghostty-config-bats.XXXXXX")"
  local path
  for path in \
    checks/ghostty.sh \
    rig/home/private_dot_config/ghostty/private_config.tmpl \
    rig/home/.chezmoidata.toml \
    rig/dots/zshrc \
    rig/home/dot_zshrc.tmpl \
    rig/home/AGENTS.md \
    justfile \
    .pre-commit-config.yaml \
    openspec/specs/ghostty-config-assurance/spec.md \
    docs/content/docs/terminal.mdx \
    docs/content/docs/validation.mdx \
    docs/content/docs/home-config.mdx \
    docs/content/docs/shell.mdx; do
    mkdir -p "$SANDBOX/$(dirname "$path")"
    cp "$REPO_ROOT/$path" "$SANDBOX/$path"
  done
}

teardown() {
  /bin/rm -rf -- "$SANDBOX"
}

@test "current Ghostty source passes isolated validation" {
  run bash "$SANDBOX/checks/ghostty.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghostty: ok"* ]]
}

@test "Chezmoi applies only the Ghostty target with private file permissions" {
  command -v chezmoi >/dev/null 2>&1 || skip "requires chezmoi"
  destination="$SANDBOX/deployed"
  target="$destination/.config/ghostty/config"
  mkdir -p "$(dirname "$target")/backgrounds"
  printf 'local overlay\n' >"$(dirname "$target")/config.local"
  printf 'local background\n' >"$(dirname "$target")/backgrounds/apex-terminal-bg-v3.png"
  run chezmoi --source "$SANDBOX/rig/home" --destination "$destination" apply "$target"
  [ "$status" -eq 0 ]
  [ -f "$target" ]
  rg -F -x -q 'local overlay' "$(dirname "$target")/config.local"
  rg -F -x -q 'local background' "$(dirname "$target")/backgrounds/apex-terminal-bg-v3.png"
  if stat -c %a "$target" >/dev/null 2>&1; then
    mode="$(stat -c %a "$target")"
  else
    mode="$(stat -f %Lp "$target")"
  fi
  [ "$mode" = 600 ]
  run chezmoi --source "$SANDBOX/rig/home" --destination "$destination" verify "$target"
  [ "$status" -eq 0 ]
}

@test "old resources marker is rejected in both zsh mirrors" {
  for path in rig/dots/zshrc rig/home/dot_zshrc.tmpl; do
    printf '\nif [[ -n "${GHOSTTY_RESOURCES_DIR:-}" ]]; then :; fi\n' >>"$SANDBOX/$path"
  done
  run bash "$SANDBOX/checks/ghostty.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must not retain the old Ghostty marker guard"* ]]
}

@test "old integration marker is rejected in both zsh mirrors" {
  for path in rig/dots/zshrc rig/home/dot_zshrc.tmpl; do
    printf '\n: ghostty-integration\n' >>"$SANDBOX/$path"
  done
  run bash "$SANDBOX/checks/ghostty.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must not retain the old Ghostty marker guard"* ]]
}

@test "macOS clipboard guidance cannot claim a separate selection clipboard" {
  printf '\ncopy-on-select = true avoids writing the macOS system clipboard.\n' \
    >>"$SANDBOX/docs/content/docs/terminal.mdx"
  run bash "$SANDBOX/checks/ghostty.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"macOS selection writes to the system clipboard"* ]]
}

@test "duplicate copy-on-select assignments fail closed" {
  printf '\ncopy-on-select = clipboard\n' \
    >>"$SANDBOX/rig/home/private_dot_config/ghostty/private_config.tmpl"
  run bash "$SANDBOX/checks/ghostty.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"copy-on-select assignment"* ]]
}

@test "pre-commit watches the private Ghostty template" {
  hook="$SANDBOX/.pre-commit-config.yaml"
  rg -v 'private_config' "$hook" >"$hook.tmp"
  mv "$hook.tmp" "$hook"
  run bash "$SANDBOX/checks/ghostty.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"pre-commit must watch the private Ghostty template"* ]]
}

@test "native titlebar is accepted with native fullscreen" {
  template="$SANDBOX/rig/home/private_dot_config/ghostty/private_config.tmpl"
  rg -F -x -q 'macos-titlebar-style = native' "$template"
  rg -F -x -q 'macos-non-native-fullscreen = false' "$template"
  run bash "$SANDBOX/checks/ghostty.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghostty: ok"* ]]
}

@test "custom tabs titlebar is rejected on macOS 27" {
  template="$SANDBOX/rig/home/private_dot_config/ghostty/private_config.tmpl"
  perl -0pi -e 's/macos-titlebar-style = native/macos-titlebar-style = tabs/' "$template"
  run bash "$SANDBOX/checks/ghostty.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"custom tabs titlebar is broken on macOS 27"* ]]
}

@test "runbook and specification acknowledge the macOS system clipboard" {
  rg -F -q 'On macOS, `copy-on-select = true` still copies selections to the system clipboard' \
    "$SANDBOX/docs/content/docs/terminal.mdx"
  rg -F -q '`copy-on-select = true` still writes selections to the macOS system clipboard' \
    "$SANDBOX/openspec/specs/ghostty-config-assurance/spec.md"
  ! rg -F -q 'prefers the selection clipboard instead of always writing the system clipboard' \
    "$SANDBOX/openspec/specs/ghostty-config-assurance/spec.md"
}
