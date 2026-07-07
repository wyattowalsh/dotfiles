#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FRESHEN_FILE="${REPO_DIR}/home/dot_zsh/functions/freshen"
TEST_FILE="${REPO_DIR}/home/dot_zsh/functions/tests/freshen_test.zsh"

if ! command -v zsh >/dev/null 2>&1; then
  printf 'zsh not installed; skipping freshen smoke\n'
  exit 0
fi

"${REPO_DIR}/checks/freshen-version.sh"
zsh -n "$FRESHEN_FILE"
FRESHEN_UNDER_TEST="$FRESHEN_FILE" zsh "$TEST_FILE"

printf 'freshen smoke checks completed.\n'
