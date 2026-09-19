#!/usr/bin/env bash
# shellcheck disable=SC2016 # Literal bootstrap contract contains a zsh variable.
# Fail when compaudit reports insecure completion directories (e.g. brew
# share/ regressing to group/world-writable, which stalls interactive shells).
# Read-only probe; bootstrap's normalize_completion_dir_perms fixes what
# this detects. Linux CI skips — this guards the macOS Homebrew layout.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="$ROOT/rig/bootstrap/macos.sh"

[[ -f "$BOOTSTRAP" ]] || {
  printf 'zsh-compaudit: missing %s\n' "$BOOTSTRAP" >&2
  exit 1
}
grep -Fq 'normalize_completion_dir_perms()' "$BOOTSTRAP" \
  || {
    printf 'zsh-compaudit: bootstrap normalization function missing\n' >&2
    exit 1
  }
grep -Fq 'run_or_print "chmod go-w completion dir: $dir" chmod go-w "$dir"' "$BOOTSTRAP" \
  || {
    printf 'zsh-compaudit: bootstrap chmod go-w contract missing\n' >&2
    exit 1
  }
[[ $(grep -Fc "autoload -Uz compaudit; compaudit" "$BOOTSTRAP") -ge 2 ]] \
  || {
    printf 'zsh-compaudit: bootstrap must audit before and after normalization\n' >&2
    exit 1
  }

case "$(uname -s)" in
  Darwin) ;;
  *)
    printf 'zsh-compaudit: skip (non-Darwin: %s)\n' "$(uname -s)"
    exit 0
    ;;
esac

ZSH_BIN="$(command -v zsh || true)"
if [[ -z "$ZSH_BIN" ]]; then
  printf 'zsh-compaudit: skip (zsh not found)\n'
  exit 0
fi

insecure="$("$ZSH_BIN" -c 'autoload -Uz compaudit; compaudit' 2>/dev/null || true)"
if [[ -n "$insecure" ]]; then
  printf 'zsh-compaudit: FAIL — insecure completion directories:\n' >&2
  printf '%s\n' "$insecure" | sed 's/^/  /' >&2
  printf 'fix: chmod go-w on the dirs above (bootstrap phase does this on --apply)\n' >&2
  exit 1
fi

printf 'zsh-compaudit: ok (completion directories secure)\n'
