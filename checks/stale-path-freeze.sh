#!/usr/bin/env bash
# Fail if live contracts still cite pre-rig/ top-level machine paths.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

hits=0

scan_file() {
  local file="$1"
  [ -f "$file" ] || return 0

  # Skip intentional policy lines that mention old paths only to forbid them.
  # Do not skip a line merely because it also contains a canonical rig/ path;
  # a stale brew/Brewfile token on the same line must still fail.
  local line_no=0
  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    case "$line" in
      *'do not reintroduce'* | *'Do not reintroduce'* | *'must not reintroduce'*) continue ;;
    esac

    if printf '%s\n' "$line" | rg -q \
      -e '(^|[^/[:alnum:]_])brew/Brewfile' \
      -e '(^|[^/[:alnum:]_])bootstrap/macos\.sh' \
      -e '(^|[^/[:alnum:]_])bootstrap/linux\.sh' \
      -e 'chezmoi --source home\b' \
      -e 'cmp -s dots/' \
      -e 'zsh -n dots/' \
      -e '\$REPO_DIR/dots/' \
      -e '\$REPO_DIR/home/' \
      -e '\$REPO_DIR/brew/' \
      -e '\./darwin#'; then
      printf 'stale-path-freeze: %s:%s: %s\n' "$file" "$line_no" "$line" >&2
      hits=$((hits + 1))
    fi
  done <"$file"
}

scan_file AGENTS.md
scan_file README.md
scan_file justfile
scan_file setup.sh
scan_file docs/AGENTS.md

while IFS= read -r -d '' f; do
  # Skip this detector (patterns are intentional string literals).
  case "$f" in
    */stale-path-freeze.sh | stale-path-freeze.sh) continue ;;
  esac
  scan_file "$f"
done < <(find checks -maxdepth 1 -type f -name '*.sh' -print0 2>/dev/null)

while IFS= read -r -d '' f; do
  scan_file "$f"
done < <(find docs/content/docs -maxdepth 1 -type f -name '*.mdx' -print0 2>/dev/null)

while IFS= read -r -d '' f; do
  scan_file "$f"
done < <(find .github -type f \( -name '*.md' -o -name '*.yml' -o -name '*.yaml' \) -print0 2>/dev/null)

while IFS= read -r -d '' f; do
  scan_file "$f"
done < <(find rig -type f -name 'AGENTS.md' -print0 2>/dev/null)

if [ -d openspec ]; then
  while IFS= read -r -d '' f; do
    scan_file "$f"
  done < <(find openspec -type f \( -name '*.md' -o -name '*.mdx' -o -name '*.yml' -o -name '*.yaml' -o -name '*.txt' \) -print0 2>/dev/null)
fi

if [ "$hits" -gt 0 ]; then
  printf 'stale-path-freeze: %s hit(s)\n' "$hits" >&2
  exit 1
fi

printf 'stale-path-freeze: ok\n'
