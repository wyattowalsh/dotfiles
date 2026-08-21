#!/usr/bin/env bash
# just check-shell-files
# Fail if justfile shell_files drifts from tracked *.sh plus the kopia runner.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JUSTFILE="$REPO_DIR/justfile"

if [[ ! -f "$JUSTFILE" ]]; then
  printf 'shell-files-sync: missing %s\n' "$JUSTFILE" >&2
  exit 1
fi

line="$(sed -n 's/^shell_files := "\(.*\)"$/\1/p' "$JUSTFILE" | head -n 1)"
if [[ -z "$line" ]]; then
  printf 'shell-files-sync: could not parse shell_files from justfile\n' >&2
  exit 1
fi

# shellcheck disable=SC2086
just_list="$(printf '%s\n' $line | LC_ALL=C sort -u)"

tracked="$(
  git -C "$REPO_DIR" ls-files -- '*.sh' 'rig/home/dot_local/bin/executable_kopia-nightly' \
    | LC_ALL=C sort -u
)"

if [[ "$just_list" != "$tracked" ]]; then
  printf 'shell-files-sync: justfile shell_files does not match tracked shell files\n' >&2
  printf '\nOnly in justfile:\n' >&2
  comm -23 <(printf '%s\n' "$just_list") <(printf '%s\n' "$tracked") >&2 || true
  printf '\nOnly in git:\n' >&2
  comm -13 <(printf '%s\n' "$just_list") <(printf '%s\n' "$tracked") >&2 || true
  exit 1
fi

printf 'shell-files-sync: ok\n'
