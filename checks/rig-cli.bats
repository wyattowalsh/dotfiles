#!/usr/bin/env bats
# CI-safe file-only Bats for shell structure, Atuin init, and just/mise boundary.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "just shell_files paths exist" {
  cd "$REPO_ROOT"
  files="$(just --evaluate shell_files)"
  [ -n "$files" ]
  for f in $files; do
    [ -f "$REPO_ROOT/$f" ]
  done
}

@test "zsh-structure fixture runner still fails bad fixtures and accepts good-minimal" {
  run "$REPO_ROOT/checks/zsh-structure-test.sh"
  [ "$status" -eq 0 ]
}

@test "canonical zshrc inits atuin without up-arrow or AI" {
  grep -Fq 'atuin init zsh --disable-up-arrow --disable-ai' "$REPO_ROOT/rig/dots/zshrc"
  grep -Fq 'atuin init zsh --disable-up-arrow --disable-ai' "$REPO_ROOT/rig/home/dot_zshrc.tmpl"
}

@test "mise-boundary refuses a rival task runner at repo root" {
  run "$REPO_ROOT/checks/mise-boundary.sh"
  [ "$status" -eq 0 ]
}
