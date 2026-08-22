#!/usr/bin/env bats
# Offline Apple Text Replacement / Shortcuts registry checks.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "apple-text validate succeeds" {
  run "$REPO_ROOT/checks/apple-text.sh" validate
  [ "$status" -eq 0 ]
  [[ "$output" == valid* ]]
}

@test "apple-text merge harness preserves unrelated replacements" {
  run "$REPO_ROOT/checks/apple-text-test.sh"
  [ "$status" -eq 0 ]
}
