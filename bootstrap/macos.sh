#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
VERBOSE=0
APPLY=0

usage() {
  cat <<'USAGE'
Usage: bootstrap/macos.sh [--dry-run] [--apply] [--verbose]

  --dry-run   Print planned macOS bootstrap actions without mutating state.
  --apply     Permit mutating setup actions.
  --verbose   Print additional diagnostics.
USAGE
}

log() {
  printf '[bootstrap] %s\n' "$*"
}

debug() {
  if [ "$VERBOSE" -eq 1 ]; then
    printf '[debug] %s\n' "$*" >&2
  fi
}

run_or_print() {
  local description="$1"
  shift

  if [ "$DRY_RUN" -eq 1 ] || [ "$APPLY" -eq 0 ]; then
    printf '[dry-run] %s: ' "$description"
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi

  log "$description"
  "$@"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --apply)
        APPLY=1
        ;;
      --verbose)
        VERBOSE=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        usage >&2
        exit 2
        ;;
    esac
    shift
  done
}

require_macos() {
  if [ "$(uname -s)" != "Darwin" ]; then
    printf 'macOS bootstrap can only run on Darwin. Use ./setup.sh for Linux.\n' >&2
    exit 1
  fi
}

ensure_command_plan() {
  local command_name="$1"
  local install_hint="$2"

  if command -v "$command_name" >/dev/null 2>&1; then
    debug "$command_name found at $(command -v "$command_name")"
    return 0
  fi

  run_or_print "Install ${command_name}" bash -lc "$install_hint"
}

main() {
  parse_args "$@"
  require_macos

  if [ "$APPLY" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    log "No --apply supplied; defaulting to dry-run preview."
    DRY_RUN=1
  fi

  log "macOS full-rig bootstrap"
  log "mode=$([ "$APPLY" -eq 1 ] && printf apply || printf dry-run)"

  if ! xcode-select -p >/dev/null 2>&1; then
    run_or_print "Install Xcode Command Line Tools" xcode-select --install
  else
    debug "Xcode Command Line Tools already installed"
  fi

  # shellcheck disable=SC2016
  ensure_command_plan brew '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  ensure_command_plan task 'brew install go-task'
  ensure_command_plan nix 'curl --proto "=https" --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install'
  ensure_command_plan chezmoi 'brew install chezmoi'
  ensure_command_plan pnpm 'brew install pnpm'

  run_or_print "Check curated Brewfile" brew bundle check --file brew/Brewfile
  run_or_print "Preview Chezmoi home changes" chezmoi --source home diff

  if command -v nix >/dev/null 2>&1; then
    run_or_print "Check nix-darwin flake" nix flake check ./darwin
  else
    log "nix unavailable; nix-darwin check remains planned."
  fi

  log "Bootstrap preview complete. Re-run with --apply after reviewing output."
}

main "$@"
