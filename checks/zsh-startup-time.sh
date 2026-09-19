#!/usr/bin/env bash
# Report interactive zsh startup time (min/median/max of N runs). Report-only.
# Usage: ./checks/zsh-startup-time.sh [runs]
set -euo pipefail

runs="${1:-5}"
if ! [[ "$runs" =~ ^[0-9]+$ ]] || ! ((runs > 0)); then
  printf 'zsh-startup-time: invalid runs: %s\n' "$runs" >&2
  exit 2
fi

if ! command -v zsh >/dev/null 2>&1; then
  printf 'zsh-startup-time: skip (zsh not found)\n'
  exit 0
fi
if [[ ! -x /usr/bin/time ]]; then
  printf 'zsh-startup-time: skip (/usr/bin/time not found)\n'
  exit 0
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/zsh-startup-time.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

# Powerlevel10k/gitstatus takes a different path without a TTY. On macOS,
# time the same pseudo-terminal startup shape used by Terminal/iTerm/Ghostty.
timing_command=(zsh -i -c exit)
if [[ $(uname -s) == Darwin && -x /usr/bin/script ]]; then
  timing_command=(/usr/bin/script -q /dev/null zsh -i -c exit)
fi

: >"$tmp_dir/all"
i=0
while ((i++ < runs)); do
  if ! /usr/bin/time -p "${timing_command[@]}" >/dev/null 2>"$tmp_dir/one"; then
    printf 'zsh-startup-time: startup run %d failed\n' "$i" >&2
    cat "$tmp_dir/one" >&2
    exit 1
  fi
  real_seconds="$(awk '/^real/ { print $2; exit }' "$tmp_dir/one")"
  if [[ -z "$real_seconds" ]]; then
    printf 'zsh-startup-time: run %d produced no timing result\n' "$i" >&2
    cat "$tmp_dir/one" >&2
    exit 1
  fi
  printf '%s\n' "$real_seconds" >>"$tmp_dir/all"
done

sort -n "$tmp_dir/all" | awk '
  { t[NR] = $1 }
  END {
    med = (NR % 2) ? t[(NR + 1) / 2] : (t[NR / 2] + t[NR / 2 + 1]) / 2
    printf "zsh-startup-time: %d runs, min %.0fms, median %.0fms, max %.0fms\n", NR, t[1] * 1000, med * 1000, t[NR] * 1000
  }'
