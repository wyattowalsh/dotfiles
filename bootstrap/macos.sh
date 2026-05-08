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

mode_name() {
  if [ "$APPLY" -eq 1 ]; then
    printf 'apply'
  else
    printf 'dry-run'
  fi
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

  if [ "$DRY_RUN" -eq 1 ] && [ "$APPLY" -eq 1 ]; then
    printf '%s\n' '--dry-run and --apply cannot be used together.' >&2
    usage >&2
    exit 2
  fi
}

load_homebrew_shellenv() {
  local brew_bin=""

  if command -v brew >/dev/null 2>&1; then
    brew_bin="$(command -v brew)"
  elif [ -x /opt/homebrew/bin/brew ]; then
    brew_bin="/opt/homebrew/bin/brew"
  elif [ -x /usr/local/bin/brew ]; then
    brew_bin="/usr/local/bin/brew"
  fi

  if [ -n "$brew_bin" ]; then
    debug "Loading Homebrew shellenv from ${brew_bin}"
    eval "$("$brew_bin" shellenv)"
  fi
}

load_nix_profile() {
  local nix_profile="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"

  if [ -f "$nix_profile" ]; then
    # shellcheck disable=SC1090
    . "$nix_profile"
  fi
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

  if [ "$command_name" = "brew" ]; then
    load_homebrew_shellenv
  elif [ "$command_name" = "nix" ]; then
    load_nix_profile
  fi

  if [ "$APPLY" -eq 1 ] && ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Required command still unavailable after install attempt: %s\n' "$command_name" >&2
    exit 1
  fi
}

main() {
  parse_args "$@"
  require_macos

  if [ "$APPLY" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    log "No --apply supplied; defaulting to dry-run preview."
    DRY_RUN=1
  fi

  log "macOS full-rig bootstrap"
  log "mode=$(mode_name)"

  if ! xcode-select -p >/dev/null 2>&1; then
    run_or_print "Install Xcode Command Line Tools" xcode-select --install
  else
    debug "Xcode Command Line Tools already installed"
  fi

  # shellcheck disable=SC2016
  ensure_command_plan brew '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  load_homebrew_shellenv
  ensure_command_plan task 'brew install go-task'
  ensure_command_plan nix 'curl --proto "=https" --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install'
  ensure_command_plan chezmoi 'brew install chezmoi'
  ensure_command_plan pnpm 'brew install pnpm'

  if [ "$APPLY" -eq 1 ]; then
    run_or_print "Install curated Brewfile" brew bundle install --file brew/Brewfile
    run_or_print "Apply Chezmoi home changes" chezmoi --source home apply
  else
    run_or_print "Check curated Brewfile" brew bundle check --file brew/Brewfile
    run_or_print "Preview Chezmoi home changes" chezmoi --source home diff
  fi

  if command -v nix >/dev/null 2>&1; then
    run_or_print "Check nix-darwin flake" nix flake check ./darwin
  else
    log "nix unavailable; nix-darwin check remains planned."
  fi

  if command -v darwin-rebuild >/dev/null 2>&1; then
    if [ "$APPLY" -eq 1 ]; then
      run_or_print "Apply nix-darwin system state" darwin-rebuild switch --flake ./darwin#w4w-mbp
    else
      run_or_print "Check nix-darwin system state" darwin-rebuild check --flake ./darwin#w4w-mbp
    fi
  else
    log "darwin-rebuild unavailable; nix-darwin switch remains planned."
  fi

  if [ "$APPLY" -eq 1 ]; then
    log "Bootstrap apply complete."
  else
    log "Bootstrap preview complete. Re-run with --apply after reviewing output."
  fi
}

main "$@"
