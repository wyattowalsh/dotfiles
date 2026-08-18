#!/usr/bin/env bash
# Fail if rig/brew/exclude.txt tokens appear as brew/cask/tap entries in rig/brew/Brewfile.
# Also fail on duplicate brew/cask basenames (last path segment after /).
# taps may share names with brew; mas vs cask overlap is not treated as a duplicate.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BREWFILE="${1:-$REPO_DIR/rig/brew/Brewfile}"
EXCLUDE="${2:-$REPO_DIR/rig/brew/exclude.txt}"

if [[ ! -f "$BREWFILE" ]]; then
  printf 'Missing Brewfile: %s\n' "$BREWFILE" >&2
  exit 1
fi
if [[ ! -f "$EXCLUDE" ]]; then
  printf 'Missing exclude list: %s\n' "$EXCLUDE" >&2
  exit 1
fi

if ! command -v rg >/dev/null 2>&1; then
  printf 'brew-exclude-check: ripgrep (rg) is required\n' >&2
  exit 1
fi

hits=0
while IFS= read -r line || [[ -n "$line" ]]; do
  # strip comments and whitespace
  token="${line%%#*}"
  token="$(printf '%s' "$token" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [[ -z "$token" ]] && continue

  if rg -q --fixed-strings "brew \"${token}\"" "$BREWFILE" \
    || rg -q --fixed-strings "cask \"${token}\"" "$BREWFILE" \
    || rg -q --fixed-strings "tap \"${token}\"" "$BREWFILE"; then
    printf 'exclude violation: %s still listed in %s\n' "$token" "$BREWFILE" >&2
    hits=$((hits + 1))
  fi
done <"$EXCLUDE"

# Duplicate brew/cask basenames (last path segment). Scan brew+cask only so
# tap/formula name sharing and mas/cask dual-channel (WhatsApp) are allowed.
list_brew_cask_basenames() {
  local line trimmed kind token base
  local line_no=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    trimmed="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//')"
    [[ -z "$trimmed" ]] && continue
    [[ "$trimmed" == \#* ]] && continue
    if [[ "$trimmed" =~ ^(brew|cask)[[:space:]]+\"([^\"]+)\" ]]; then
      kind="${BASH_REMATCH[1]}"
      token="${BASH_REMATCH[2]}"
      base="${token##*/}"
      printf '%s\t%s\t%s\t%s\n' "$kind" "$base" "$line_no" "$token"
    fi
  done <"$BREWFILE"
}

dup_hits=0
dup_report="$(
  list_brew_cask_basenames | awk '
    BEGIN { FS = OFS = "\t" }
    {
      key = $1 SUBSEP $2
      count[key]++
      rec[key] = rec[key] sprintf("  %s \"%s\" (line %s)\n", $1, $4, $3)
    }
    END {
      nkeys = 0
      for (k in count) {
        if (count[k] > 1) {
          nkeys++
          split(k, a, SUBSEP)
          printf "duplicate %s basename: %s\n%s", a[1], a[2], rec[k]
        }
      }
      if (nkeys > 0) {
        printf "DUP_COUNT %d\n", nkeys
      }
    }
  '
)"

if [[ -n "$dup_report" ]]; then
  while IFS= read -r report_line || [[ -n "$report_line" ]]; do
    if [[ "$report_line" == DUP_COUNT* ]]; then
      dup_hits="${report_line#DUP_COUNT }"
      continue
    fi
    printf '%s\n' "$report_line" >&2
  done <<<"$dup_report"
fi

if [[ "$hits" -gt 0 || "$dup_hits" -gt 0 ]]; then
  if [[ "$hits" -gt 0 ]]; then
    printf 'brew-exclude-check: %s violation(s)\n' "$hits" >&2
  fi
  if [[ "$dup_hits" -gt 0 ]]; then
    printf 'brew-exclude-check: %s duplicate basename(s)\n' "$dup_hits" >&2
  fi
  exit 1
fi

printf 'brew-exclude-check: ok\n'
