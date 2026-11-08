#!/usr/bin/env bash
# Legacy QoL installs are retired. Existing snapshots remain available for review.
set -euo pipefail

STATE="${IINA_QOL_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/iina-qol}"
case "${1:-preview}" in
  preview | doctor)
    printf 'iina-qol: retired; custom plugin/bridge source is not installed\n'
    printf 'iina-qol: use checks/iina-native.sh preview for the native migration\n'
    if [[ -d "$STATE" ]]; then printf 'iina-qol: legacy backups remain at %s\n' "$STATE"; fi
    ;;
  apply)
    printf 'iina-qol: apply disabled; use checks/iina-native.sh preview first\n' >&2
    exit 1
    ;;
  restore)
    printf 'iina-qol: legacy backup restore requires manual review; this retired runner will not write arbitrary paths from old snapshots\n' >&2
    printf 'iina-qol: inspect %s and use the reviewed native migration restore for new snapshots\n' "$STATE" >&2
    exit 1
    ;;
  *)
    printf 'iina-qol: unknown command %s\n' "$1" >&2
    exit 1
    ;;
esac
