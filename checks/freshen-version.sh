#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FRESHEN_FILE="${REPO_DIR}/home/dot_zsh/functions/freshen"
VERSION_FILE="${REPO_DIR}/home/dot_zsh/functions/freshen.VERSION"
TEST_FILE="${REPO_DIR}/home/dot_zsh/functions/tests/freshen_test.zsh"

if [[ ! -r "$VERSION_FILE" ]]; then
  printf 'Missing freshen.VERSION: %s\n' "$VERSION_FILE" >&2
  exit 1
fi

EXPECTED_VERSION="$(sed -n '1p' "$VERSION_FILE")"
EXPECTED_DATE="$(sed -n '2p' "$VERSION_FILE")"

if [[ -z "$EXPECTED_VERSION" ]]; then
  printf 'freshen.VERSION must include a version on line 1\n' >&2
  exit 1
fi

if ! grep -Fq "# freshen v${EXPECTED_VERSION}" "$FRESHEN_FILE"; then
  printf 'freshen header missing version v%s\n' "$EXPECTED_VERSION" >&2
  exit 1
fi

# shellcheck disable=SC2016
if ! grep -Fq 'print "freshen ${_FRESHEN_VERSION} (${_FRESHEN_RELEASE_DATE})"' "$FRESHEN_FILE"; then
  printf 'freshen --version emit missing dynamic version from freshen.VERSION\n' >&2
  exit 1
fi

if ! grep -Fq "freshen ${EXPECTED_VERSION}" "$TEST_FILE"; then
  printf 'freshen_test.zsh missing version assertion for %s\n' "$EXPECTED_VERSION" >&2
  exit 1
fi

printf 'freshen version SSOT OK: %s (%s)\n' "$EXPECTED_VERSION" "$EXPECTED_DATE"
