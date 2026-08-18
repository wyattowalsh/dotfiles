#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
VERBOSE=0
APPLY=0
NO_UPGRADE=0
WITH_DEV_ENV=0
REQUIRE_DEV_ENV=0
DRY_RUN_FAILED=0
SUDO_KEEPALIVE_PID=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RIG_DIR="$REPO_ROOT/rig"
BREWFILE="$RIG_DIR/brew/Brewfile"
DARWIN_FLAKE="$RIG_DIR/darwin"
DOTS_DIR="$RIG_DIR/dots"
HOME_SOURCE="$RIG_DIR/home"
DARWIN_HOST="${DARWIN_HOST:-w4w-mbp}"

usage() {
  cat <<'USAGE'
Usage: rig/bootstrap/macos.sh [--dry-run] [--apply] [--verbose] [--no-upgrade] [--with-dev-env] [--require-dev-env]

  --dry-run          Print planned macOS bootstrap actions without mutating state.
  --apply            Permit mutating setup actions.
  --verbose          Print additional diagnostics.
  --no-upgrade       Pass --no-upgrade to brew bundle install (safer first restore).
  --with-dev-env     Also run the portable agent-stack installer (just bootstrap-dev).
  --require-dev-env  Fail if --with-dev-env is set and the agent-stack installer fails.
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

# Execute known-safe read-only probes even in dry-run when the tool exists.
# Accumulate failures and finish the plan; main exits non-zero if any failed.
run_readonly() {
  local description="$1"
  shift

  printf '[check] %s: ' "$description"
  printf '%q ' "$@"
  printf '\n'

  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'skip: %s not installed\n' "$1"
    return 0
  fi

  if ! "$@"; then
    DRY_RUN_FAILED=1
    printf 'check failed: %s\n' "$description" >&2
    return 0
  fi
}

mode_name() {
  if [ "$APPLY" -eq 1 ]; then
    printf 'apply'
  else
    printf 'dry-run'
  fi
}

cleanup() {
  if [ -n "$SUDO_KEEPALIVE_PID" ] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

keep_sudo_alive() {
  if [ "$APPLY" -ne 1 ]; then
    return 0
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    return 0
  fi
  if ! sudo -n true 2>/dev/null; then
    sudo -v || true
  fi
  (
    while true; do
      sleep 60
      sudo -n true 2>/dev/null || exit 0
    done
  ) >/dev/null 2>&1 &
  SUDO_KEEPALIVE_PID=$!
  debug "sudo keepalive pid=${SUDO_KEEPALIVE_PID}"
}

nix_darwin_command() {
  if command -v darwin-rebuild >/dev/null 2>&1; then
    darwin-rebuild "$@"
    return
  fi

  if [ ! -f "$DARWIN_FLAKE/flake.lock" ]; then
    printf 'darwin-rebuild is unavailable and %s is missing. Run: nix flake lock %s\n' "$DARWIN_FLAKE/flake.lock" "$DARWIN_FLAKE" >&2
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    printf 'jq is required to read the pinned nix-darwin revision from %s.\n' "$DARWIN_FLAKE/flake.lock" >&2
    return 1
  fi

  local owner repo rev
  owner="$(jq -r '.nodes."nix-darwin".locked.owner // empty' "$DARWIN_FLAKE/flake.lock")"
  repo="$(jq -r '.nodes."nix-darwin".locked.repo // empty' "$DARWIN_FLAKE/flake.lock")"
  rev="$(jq -r '.nodes."nix-darwin".locked.rev // empty' "$DARWIN_FLAKE/flake.lock")"

  if [ -z "$owner" ] || [ -z "$repo" ] || [ -z "$rev" ]; then
    printf 'Unable to read pinned nix-darwin owner, repo, and revision from %s.\n' "$DARWIN_FLAKE/flake.lock" >&2
    return 1
  fi

  nix run "github:${owner}/${repo}/${rev}#darwin-rebuild" -- "$@"
}

require_darwin_flake_lock() {
  if [ -f "$DARWIN_FLAKE/flake.lock" ]; then
    return 0
  fi

  printf 'Missing %s. Generate and commit it with: nix flake lock %s\n' "$DARWIN_FLAKE/flake.lock" "$DARWIN_FLAKE" >&2
  return 1
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
      --no-upgrade)
        NO_UPGRADE=1
        ;;
      --with-dev-env)
        WITH_DEV_ENV=1
        ;;
      --require-dev-env)
        REQUIRE_DEV_ENV=1
        WITH_DEV_ENV=1
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

require_non_root() {
  if [ "$(id -u)" -eq 0 ]; then
    printf 'Do not run bootstrap as root. Run as your normal user (sudo is used only where required).\n' >&2
    exit 1
  fi
}

# CLT poll: 5s interval × 360 ≈ 30 minutes max (RV-001).
CLT_WAIT_INTERVAL_SEC="${CLT_WAIT_INTERVAL_SEC:-5}"
CLT_WAIT_MAX_ATTEMPTS="${CLT_WAIT_MAX_ATTEMPTS:-360}"

ensure_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    debug "Xcode Command Line Tools already installed"
    return 0
  fi

  run_or_print "Install Xcode Command Line Tools" xcode-select --install

  if [ "$APPLY" -eq 1 ]; then
    log "Waiting for Xcode Command Line Tools (max ~$((CLT_WAIT_INTERVAL_SEC * CLT_WAIT_MAX_ATTEMPTS / 60)) min)..."
    local attempt=0
    until xcode-select -p >/dev/null 2>&1; do
      attempt=$((attempt + 1))
      if [ "$attempt" -ge "$CLT_WAIT_MAX_ATTEMPTS" ]; then
        printf 'Timed out waiting for Xcode Command Line Tools after %s attempts.\n' "$CLT_WAIT_MAX_ATTEMPTS" >&2
        printf 'Finish the CLT install UI (or run: xcode-select --install), then re-run: just bootstrap --apply\n' >&2
        exit 1
      fi
      sleep "$CLT_WAIT_INTERVAL_SEC"
    done
    log "Xcode Command Line Tools ready"
  fi
}

# Oh My Zsh installer URL (override to pin a commit). Default matches setup.sh.
# Supply-chain note: this is still an upstream script; pin via OMZ_INSTALL_URL when needed (RV-003).
OMZ_INSTALL_URL="${OMZ_INSTALL_URL:-https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh}"

ensure_oh_my_zsh_and_p10k() {
  local zsh_dir="${ZSH:-$HOME/.oh-my-zsh}"
  local custom_dir="${ZSH_CUSTOM:-$zsh_dir/custom}"
  local theme_dir="$custom_dir/themes/powerlevel10k"
  local installer=""

  # Tracked dots/zshrc sources Oh My Zsh + powerlevel10k; ensure they exist.
  # Do not clone brew-managed zsh-autosuggestions / zsh-syntax-highlighting into OMZ custom.
  if [ ! -d "$zsh_dir" ]; then
    if [ "$DRY_RUN" -eq 1 ] || [ "$APPLY" -eq 0 ]; then
      printf '[dry-run] Install Oh My Zsh: download installer from %s then RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh <installer>\n' "$OMZ_INSTALL_URL"
    else
      log "Install Oh My Zsh"
      installer="$(mktemp)"
      if ! curl -fsSL "$OMZ_INSTALL_URL" -o "$installer"; then
        printf 'Failed to download Oh My Zsh installer from %s\n' "$OMZ_INSTALL_URL" >&2
        rm -f "$installer"
        exit 1
      fi
      if ! env RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh "$installer"; then
        printf 'Oh My Zsh installer failed\n' >&2
        rm -f "$installer"
        exit 1
      fi
      rm -f "$installer"
    fi
  else
    debug "Oh My Zsh already present at $zsh_dir"
  fi

  if [ ! -d "$theme_dir" ]; then
    run_or_print "Create Powerlevel10k parent directory" mkdir -p "$custom_dir/themes"
    run_or_print "Install Powerlevel10k theme" \
      git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$theme_dir"
  else
    debug "Powerlevel10k already present at $theme_dir"
  fi
}

brew_bundle_install_or_check() {
  local -a cmd

  if [ "$APPLY" -eq 1 ]; then
    cmd=(brew bundle install --file "$BREWFILE" --jobs auto)
    if [ "$NO_UPGRADE" -eq 1 ]; then
      cmd+=(--no-upgrade)
    fi
    run_or_print "Install Brewfile (transfer intent)" "${cmd[@]}"
  else
    run_readonly "Check Brewfile" brew bundle check --file "$BREWFILE"
  fi
}

link_repo_file() {
  local source_path="$1"
  local target_path="$2"

  if [ ! -e "$source_path" ]; then
    printf 'Missing source file: %s\n' "$source_path" >&2
    return 1
  fi

  if [ -L "$target_path" ]; then
    local current_target
    current_target="$(readlink "$target_path")"
    if [ "$current_target" = "$source_path" ]; then
      debug "Symlink already correct: $target_path"
      return 0
    fi
  elif [ -e "$target_path" ] && [ ! -L "$target_path" ]; then
    if [ "$APPLY" -eq 1 ]; then
      printf 'Refusing to replace non-symlink target: %s\n' "$target_path" >&2
      return 1
    fi
    printf 'would-block: non-symlink target (skip link in dry-run): %s\n' "$target_path" >&2
    return 0
  fi

  local target_dir
  target_dir="$(dirname "$target_path")"
  if [ ! -d "$target_dir" ]; then
    run_or_print "Create directory $target_dir" mkdir -p "$target_dir"
  fi

  run_or_print "Link $(basename "$target_path")" ln -sfn "$source_path" "$target_path"
}

link_root_dotfiles() {
  link_repo_file "$DOTS_DIR/zshrc" "$HOME/.zshrc"
  link_repo_file "$DOTS_DIR/p10k.zsh" "$HOME/.p10k.zsh"
  link_repo_file "$DOTS_DIR/gitconfig" "$HOME/.gitconfig"
  link_repo_file "$DOTS_DIR/ripgreprc" "$HOME/.ripgreprc"
  link_repo_file "$DOTS_DIR/editorconfig" "$HOME/.editorconfig"
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
  require_non_root

  if [ "$APPLY" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    log "No --apply supplied; defaulting to dry-run preview."
    DRY_RUN=1
  fi

  log "macOS full-rig bootstrap"
  log "mode=$(mode_name) no_upgrade=$NO_UPGRADE"

  if [ "$APPLY" -eq 1 ]; then
    require_darwin_flake_lock
    keep_sudo_alive
  fi

  ensure_xcode_clt

  # shellcheck disable=SC2016
  ensure_command_plan brew '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  load_homebrew_shellenv
  ensure_command_plan just 'brew install just'
  ensure_command_plan nix 'curl --proto "=https" --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install'
  ensure_command_plan chezmoi 'brew install chezmoi'

  ensure_oh_my_zsh_and_p10k
  brew_bundle_install_or_check

  if [ "$APPLY" -eq 1 ]; then
    link_root_dotfiles
    run_or_print "Apply Chezmoi home changes" chezmoi --source "$HOME_SOURCE" apply
  else
    link_root_dotfiles
    run_readonly "Preview Chezmoi home changes" chezmoi --source "$HOME_SOURCE" diff
  fi

  kopia_nightly_src="$HOME_SOURCE/dot_local/bin/executable_kopia-nightly"
  if [ "$(uname -s)" = "Darwin" ] && [ -x "$kopia_nightly_src" ]; then
    if [ "$APPLY" -eq 1 ]; then
      KOPIA_NIGHTLY_REPO="$REPO_ROOT" run_or_print "Install Kopia nightly LaunchAgent" "$kopia_nightly_src" install
    else
      KOPIA_NIGHTLY_REPO="$REPO_ROOT" run_readonly "Preview Kopia nightly LaunchAgent" "$kopia_nightly_src" install --dry-run
    fi
  else
    log "Kopia nightly install skipped (non-Darwin or runner source missing)."
  fi

  if [ "$APPLY" -eq 1 ]; then
    if command -v nix >/dev/null 2>&1; then
      run_or_print "Check nix-darwin flake" nix flake check --no-write-lock-file "$DARWIN_FLAKE"
    else
      log "nix unavailable; nix-darwin check remains planned."
    fi
  else
    run_readonly "Check nix-darwin flake" nix flake check --no-write-lock-file "$DARWIN_FLAKE"
  fi

  if command -v darwin-rebuild >/dev/null 2>&1 || command -v nix >/dev/null 2>&1; then
    if [ "$APPLY" -eq 1 ]; then
      run_or_print "Apply nix-darwin system state" nix_darwin_command switch --flake "$DARWIN_FLAKE#$DARWIN_HOST"
    else
      # nix_darwin_command may resolve to a multi-word wrapper; print plan only for apply-path tools.
      if command -v darwin-rebuild >/dev/null 2>&1; then
        run_readonly "Check nix-darwin system state" darwin-rebuild check --flake "$DARWIN_FLAKE#$DARWIN_HOST"
      else
        run_or_print "Check nix-darwin system state" nix_darwin_command check --flake "$DARWIN_FLAKE#$DARWIN_HOST"
      fi
    fi
  else
    log "nix unavailable; nix-darwin switch remains planned."
  fi

  if [ "$WITH_DEV_ENV" -eq 1 ]; then
    local -a dev_args=()
    if [ "$APPLY" -eq 1 ]; then
      dev_args+=(--apply)
    else
      dev_args+=(--dry-run)
    fi
    if [ "$VERBOSE" -eq 1 ]; then
      dev_args+=(--verbose)
    fi
    dev_args+=(--skip-mcphub)
    if bash "$REPO_ROOT/rig/bootstrap/dev-env.sh" "${dev_args[@]}"; then
      log "Agent-stack installer finished."
    else
      if [ "$REQUIRE_DEV_ENV" -eq 1 ]; then
        printf 'Agent-stack installer failed (--require-dev-env).\n' >&2
        exit 1
      fi
      log "Agent-stack installer failed; continuing. Re-run: just bootstrap-dev --dry-run"
    fi
  else
    log "Agent stack is a separate step: just bootstrap-dev --dry-run"
  fi

  if [ "$APPLY" -eq 1 ]; then
    log "Bootstrap apply complete."
  else
    log "Bootstrap preview complete. Re-run with --apply after reviewing output."
    if [ "$DRY_RUN_FAILED" -eq 1 ]; then
      printf 'bootstrap dry-run/check failures occurred\n' >&2
      exit 1
    fi
  fi
}

main "$@"
