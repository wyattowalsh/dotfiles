#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"
APT_UPDATED=0

DRY_RUN=0
VERBOSE=0
SMOKE_CHECK=0

ACTIONS_RUN=0
ACTIONS_SKIPPED=0
WARNINGS=0
ERRORS=0

NETWORK_RETRY_ATTEMPTS=3
NETWORK_RETRY_BASE_DELAY=2
NETWORK_TIMEOUT_SECONDS=120

APT_COMMON_OPTS=(-o Dpkg::Use-Pty=0 -o Acquire::Retries=3)
APT_INSTALL_OPTS=(-y "${APT_COMMON_OPTS[@]}")

OS_NAME=""
ARCH_RAW=""
ARCH_NAME=""
IS_LINUX=0

LOCK_FILE="${XDG_RUNTIME_DIR:-$HOME/.cache}/dotfiles/setup.lock"
LOCK_FALLBACK_DIR="${LOCK_FILE}.lockdir"
LOCK_FD=9
LOCK_METHOD=""

export PATH="$LOCAL_BIN:$PATH"

usage() {
  cat <<'USAGE'
Usage: setup.sh [--dry-run] [--verbose] [--smoke-check]
  --dry-run      Print actions without mutating system state
  --verbose      Enable verbose debug logging
  --smoke-check  Run verification checks only (no setup mutations)
  -h, --help     Show this help message
USAGE
}

info() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf '[WARN] %s\n' "$*" >&2
}

error() {
  ERRORS=$((ERRORS + 1))
  printf '[ERROR] %s\n' "$*" >&2
}

debug() {
  if [ "$VERBOSE" -eq 1 ]; then
    printf '[DEBUG] %s\n' "$*" >&2
  fi
}

command_to_string() {
  local -a quoted=()
  local part
  for part in "$@"; do
    quoted+=("$(printf '%q' "$part")")
  done
  printf '%s' "${quoted[*]}"
}

mark_action_run() {
  ACTIONS_RUN=$((ACTIONS_RUN + 1))
}

mark_action_skipped() {
  ACTIONS_SKIPPED=$((ACTIONS_SKIPPED + 1))
}

skip_action() {
  mark_action_skipped
  info "Skipping: $*"
}

run_action() {
  local description="$1"
  shift

  local rendered
  rendered="$(command_to_string "$@")"

  if [ "$DRY_RUN" -eq 1 ]; then
    mark_action_skipped
    info "[dry-run] ${description}: ${rendered}"
    return 0
  fi

  info "$description"
  debug "Command: ${rendered}"
  "$@" || return $?
  mark_action_run
}

run_with_timeout() {
  local cmd="$1"
  local cmd_type
  cmd_type="$(type -t "$cmd" 2>/dev/null || true)"

  if [ "$cmd_type" = "file" ] && command -v timeout >/dev/null 2>&1; then
    timeout "${NETWORK_TIMEOUT_SECONDS}s" "$@"
  else
    "$@"
  fi
}

retry_with_backoff() {
  local description="$1"
  shift

  local attempt=1
  local delay="$NETWORK_RETRY_BASE_DELAY"
  local rc=0

  while [ "$attempt" -le "$NETWORK_RETRY_ATTEMPTS" ]; do
    debug "Attempt ${attempt}/${NETWORK_RETRY_ATTEMPTS}: ${description}"
    if run_with_timeout "$@"; then
      return 0
    fi

    rc=$?
    if [ "$attempt" -lt "$NETWORK_RETRY_ATTEMPTS" ]; then
      warn "${description} failed (attempt ${attempt}/${NETWORK_RETRY_ATTEMPTS}); retrying in ${delay}s."
      sleep "$delay"
      delay=$((delay * 2))
    fi

    attempt=$((attempt + 1))
  done

  return "$rc"
}

is_network_or_auth_error() {
  printf '%s' "$1" | grep -Eqi 'auth|unauthorized|forbidden|network|timeout|timed out|eai_again|enotfound|econnrefused|econnreset|401|403|could not resolve host|could not resolve hostname|name or service not known|failed to clone|repository not found|could not read from remote repository'
}

have_privilege() {
  [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1
}

require_privilege() {
  local action="$1"
  if have_privilege; then
    return 0
  fi

  error "Root/sudo is required for ${action}, but sudo is unavailable."
  return 1
}

run_privileged() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    error "This action requires root privileges: $*"
    return 1
  fi
}

detect_platform() {
  OS_NAME="$(uname -s)"
  ARCH_RAW="$(uname -m)"

  if [ "$OS_NAME" = "Linux" ]; then
    IS_LINUX=1
  else
    warn "Unsupported OS for full setup: ${OS_NAME}. Linux-only steps will be skipped."
  fi

  case "$ARCH_RAW" in
    x86_64|amd64) ARCH_NAME="amd64" ;;
    aarch64|arm64) ARCH_NAME="arm64" ;;
    *)
      ARCH_NAME="unknown"
      warn "Unsupported architecture for some installs: ${ARCH_RAW}."
      ;;
  esac

  debug "Platform detected: os=${OS_NAME} arch=${ARCH_RAW} normalized=${ARCH_NAME}"
}

acquire_setup_lock() {
  mkdir -p "$(dirname "$LOCK_FILE")"

  if command -v flock >/dev/null 2>&1; then
    eval "exec ${LOCK_FD}>\"$LOCK_FILE\""
    if flock -n "$LOCK_FD"; then
      LOCK_METHOD="flock"
      debug "Acquired flock lock: $LOCK_FILE"
      return 0
    fi

    error "Another setup.sh process is already running (lock: $LOCK_FILE)."
    return 1
  fi

  if mkdir "$LOCK_FALLBACK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_FALLBACK_DIR/pid"
    LOCK_METHOD="mkdir"
    debug "Acquired mkdir lock: $LOCK_FALLBACK_DIR"
    return 0
  fi

  if [ -f "$LOCK_FALLBACK_DIR/pid" ]; then
    local lock_pid claim_dir
    lock_pid="$(cat "$LOCK_FALLBACK_DIR/pid" 2>/dev/null || true)"
    if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
      claim_dir="${LOCK_FALLBACK_DIR}.stale.$$"
      if mv "$LOCK_FALLBACK_DIR" "$claim_dir" 2>/dev/null; then
        warn "Removing stale setup lock from PID $lock_pid."
        rm -rf "$claim_dir"
        if mkdir "$LOCK_FALLBACK_DIR" 2>/dev/null; then
          printf '%s\n' "$$" > "$LOCK_FALLBACK_DIR/pid"
          LOCK_METHOD="mkdir"
          debug "Recovered stale mkdir lock: $LOCK_FALLBACK_DIR"
          return 0
        fi
      fi
    fi
  fi

  error "Another setup.sh process is already running (lock: $LOCK_FALLBACK_DIR)."
  return 1
}

release_setup_lock() {
  case "$LOCK_METHOD" in
    flock)
      flock -u "$LOCK_FD" >/dev/null 2>&1 || true
      eval "exec ${LOCK_FD}>&-"
      ;;
    mkdir)
      rm -rf "$LOCK_FALLBACK_DIR" || true
      ;;
  esac
}

print_summary() {
  info "Summary: actions_run=${ACTIONS_RUN} skipped=${ACTIONS_SKIPPED} warnings=${WARNINGS} errors=${ERRORS}"
}

cleanup() {
  local rc=$?
  release_setup_lock

  if [ "$rc" -ne 0 ]; then
    ERRORS=$((ERRORS + 1))
    printf '[ERROR] setup.sh failed with exit code %s\n' "$rc" >&2
  fi

  print_summary
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --verbose)
        VERBOSE=1
        ;;
      --smoke-check)
        SMOKE_CHECK=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        usage >&2
        return 1
        ;;
    esac
    shift
  done
}

have_cmd() {
  case "$1" in
    bat) command -v bat >/dev/null 2>&1 || command -v batcat >/dev/null 2>&1 ;;
    fd) command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1 ;;
    *) command -v "$1" >/dev/null 2>&1 ;;
  esac
}

needs_privileged_actions() {
  if [ "$IS_LINUX" -ne 1 ]; then
    return 1
  fi

  if command -v apt-get >/dev/null 2>&1; then
    local -a missing=()
    have_cmd curl || missing+=(curl)
    have_cmd wget || missing+=(wget)
    have_cmd unzip || missing+=(unzip)
    have_cmd zsh || missing+=(zsh)
    have_cmd fzf || missing+=(fzf)
    have_cmd bat || missing+=(bat)
    have_cmd fd || missing+=(fd-find)
    have_cmd rg || missing+=(ripgrep)
    have_cmd delta || missing+=(git-delta)
    have_cmd direnv || missing+=(direnv)
    have_cmd jq || missing+=(jq)

    if [ "${#missing[@]}" -gt 0 ]; then
      return 0
    fi
  fi

  if ! command -v go >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v eza >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v lazygit >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v zoxide >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v yazi >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

run_preflight_checks() {
  info "Running preflight checks"

  local failed=0
  local -a required_sources=(
    "$REPO_DIR/.zshrc"
    "$REPO_DIR/.p10k.zsh"
    "$REPO_DIR/.gitconfig"
    "$REPO_DIR/.ripgreprc"
    "$REPO_DIR/.editorconfig"
    "$REPO_DIR/.copilot/lsp-config.json"
    "$REPO_DIR/.copilot/mcp-config.json"
    "$REPO_DIR/.claude/CLAUDE.md"
    "$REPO_DIR/.config/claude/mcp.json"
  )

  if ! command -v git >/dev/null 2>&1; then
    error "git is required but not installed."
    failed=1
  fi

  if ! command -v curl >/dev/null 2>&1; then
    error "curl is required but not installed."
    failed=1
  fi

  local source
  for source in "${required_sources[@]}"; do
    if [ ! -e "$source" ]; then
      error "Missing required source file: $source"
      failed=1
    fi
  done

  if [ "$DRY_RUN" -eq 0 ] && [ "$SMOKE_CHECK" -eq 0 ] && needs_privileged_actions && ! have_privilege; then
    error "This run requires privileged installs, but neither root nor sudo is available."
    failed=1
  fi

  if [ "$failed" -ne 0 ]; then
    return 1
  fi
}

verify_symlink() {
  local source="$1"
  local target="$2"

  if [ -L "$target" ]; then
    local linked
    linked="$(readlink "$target")"
    if [ "$linked" = "$source" ]; then
      debug "Symlink OK: $target -> $source"
      return 0
    fi

    warn "Symlink mismatch: $target -> $linked (expected $source)"
    return 1
  fi

  if [ -e "$target" ]; then
    warn "Path exists but is not a symlink: $target"
  else
    warn "Expected symlink missing: $target"
  fi

  return 1
}

run_smoke_checks() {
  info "Running smoke verification checks"

  local failed=0
  local -a expected_links=(
    "$REPO_DIR/.zshrc:$HOME/.zshrc"
    "$REPO_DIR/.p10k.zsh:$HOME/.p10k.zsh"
    "$REPO_DIR/.gitconfig:$HOME/.gitconfig"
    "$REPO_DIR/.ripgreprc:$HOME/.ripgreprc"
    "$REPO_DIR/.editorconfig:$HOME/.editorconfig"
    "$REPO_DIR/.copilot/lsp-config.json:$HOME/.copilot/lsp-config.json"
    "$REPO_DIR/.copilot/mcp-config.json:$HOME/.copilot/mcp-config.json"
    "$REPO_DIR/.claude/CLAUDE.md:$HOME/.claude/CLAUDE.md"
    "$REPO_DIR/.config/claude/mcp.json:$HOME/.config/claude/mcp.json"
  )

  local mapping source target
  for mapping in "${expected_links[@]}"; do
    source="${mapping%%:*}"
    target="${mapping#*:}"
    verify_symlink "$source" "$target" || failed=1
  done

  if [ "$failed" -ne 0 ]; then
    return 1
  fi
}

ensure_local_bin() {
  if [ -d "$LOCAL_BIN" ]; then
    skip_action "$LOCAL_BIN already exists"
    return
  fi

  run_action "Creating local bin directory" mkdir -p "$LOCAL_BIN"
}

is_yarn_apt_key_failure() {
  local output="$1"
  printf '%s' "$output" | grep -Fq 'https://dl.yarnpkg.com/debian' \
    && printf '%s' "$output" | grep -Fq 'NO_PUBKEY 62D54FD4003F6525'
}

remove_stale_yarn_apt_sources() {
  local removed=0
  local file
  local -a candidates=(
    /etc/apt/sources.list
    /etc/apt/sources.list.d/*.list
    /etc/apt/sources.list.d/*.sources
  )

  for file in "${candidates[@]}"; do
    [ -e "$file" ] || continue
    if run_privileged grep -Fq 'dl.yarnpkg.com/debian' "$file"; then
      if [ "$(basename "$file")" = "sources.list" ]; then
        run_action "Removing Yarn apt source entry from ${file}" run_privileged sed -i '/dl\.yarnpkg\.com\/debian/d' "$file"
      else
        run_action "Removing stale Yarn apt source file ${file}" run_privileged rm -f "$file"
      fi
      removed=1
    fi
  done

  if [ "$removed" -eq 0 ]; then
    warn "Detected Yarn key failure but found no Yarn apt source entries to remove."
  fi
}

ensure_apt_updated() {
  if [ "$APT_UPDATED" -eq 1 ]; then
    return
  fi

  if [ "$IS_LINUX" -ne 1 ] || ! command -v apt-get >/dev/null 2>&1; then
    return
  fi

  require_privilege "apt-get update" || return 1
  local apt_update_output
  if apt_update_output="$(run_action "Updating apt package index" run_privileged env DEBIAN_FRONTEND=noninteractive apt-get "${APT_COMMON_OPTS[@]}" update 2>&1)"; then
    APT_UPDATED=1
    return
  fi

  if is_yarn_apt_key_failure "$apt_update_output"; then
    warn "Detected stale Yarn apt repo key; removing stale Yarn apt source entries and retrying apt-get update once."
    remove_stale_yarn_apt_sources
    local retry_output
    if retry_output="$(run_action "Retrying apt package index update" run_privileged env DEBIAN_FRONTEND=noninteractive apt-get "${APT_COMMON_OPTS[@]}" update 2>&1)"; then
      APT_UPDATED=1
      return
    fi
    printf '%s\n' "$retry_output" >&2
    return 1
  fi

  printf '%s\n' "$apt_update_output" >&2
  return 1
}

install_apt_tools() {
  if [ "$IS_LINUX" -ne 1 ]; then
    warn "apt-get installs are only supported on Linux; skipping apt package installs."
    mark_action_skipped
    return
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    warn "apt-get not found; skipping apt package installs."
    mark_action_skipped
    return
  fi

  local -a missing=()
  have_cmd curl || missing+=(curl)
  have_cmd wget || missing+=(wget)
  have_cmd unzip || missing+=(unzip)
  have_cmd zsh || missing+=(zsh)
  have_cmd fzf || missing+=(fzf)
  have_cmd bat || missing+=(bat)
  have_cmd fd || missing+=(fd-find)
  have_cmd rg || missing+=(ripgrep)
  have_cmd delta || missing+=(git-delta)
  have_cmd direnv || missing+=(direnv)
  have_cmd jq || missing+=(jq)

  if [ "${#missing[@]}" -eq 0 ]; then
    skip_action "APT packages already installed"
    return
  fi

  require_privilege "apt package installation" || return 1
  ensure_apt_updated
  run_action "Installing apt packages: ${missing[*]}" run_privileged env DEBIAN_FRONTEND=noninteractive apt-get "${APT_INSTALL_OPTS[@]}" install "${missing[@]}"
}

github_asset_url() {
  local repo="$1"
  local regex="$2"
  local release_json

  release_json="$(retry_with_backoff "Fetch latest release metadata for ${repo}" curl -fsSL "https://api.github.com/repos/${repo}/releases/latest")"
  printf '%s\n' "$release_json" \
    | jq -r --arg regex "$regex" '.assets[] | select(.name | test($regex)) | .browser_download_url' \
    | head -n1
}

install_tar_binary_from_github() {
  local repo="$1"
  local regex="$2"
  local binary="$3"

  if command -v "$binary" >/dev/null 2>&1; then
    skip_action "${binary} already installed"
    return
  fi

  if [ "$IS_LINUX" -ne 1 ]; then
    warn "Skipping ${binary}; unsupported OS: ${OS_NAME}."
    mark_action_skipped
    return
  fi

  require_privilege "installing ${binary} into /usr/local/bin" || return 1

  if [ "$DRY_RUN" -eq 1 ]; then
    skip_action "Would install ${binary} from ${repo}"
    return
  fi

  local url
  url="$(github_asset_url "$repo" "$regex")"
  if [ -z "$url" ]; then
    error "Could not find ${binary} release asset for ${repo}."
    return 1
  fi

  local tmpdir archive binary_path
  tmpdir="$(mktemp -d)"
  archive="$tmpdir/archive.tar.gz"

  if ! retry_with_backoff "Download ${binary} archive" curl -fsSL "$url" -o "$archive"; then
    rm -rf "$tmpdir"
    return 1
  fi

  tar -xzf "$archive" -C "$tmpdir"
  binary_path="$(find "$tmpdir" -type f -name "$binary" | head -n1)"

  if [ -z "$binary_path" ]; then
    error "Binary ${binary} not found in downloaded archive from ${repo}."
    rm -rf "$tmpdir"
    return 1
  fi

  run_privileged install -m 755 "$binary_path" "/usr/local/bin/${binary}"
  rm -rf "$tmpdir"
  mark_action_run
}

install_deb_from_github() {
  local repo="$1"
  local regex="$2"
  local check_cmd="$3"

  if command -v "$check_cmd" >/dev/null 2>&1; then
    skip_action "${check_cmd} already installed"
    return
  fi

  if [ "$IS_LINUX" -ne 1 ]; then
    warn "Skipping ${check_cmd}; unsupported OS: ${OS_NAME}."
    mark_action_skipped
    return
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    warn "apt-get not found; cannot install ${check_cmd} from ${repo}."
    mark_action_skipped
    return
  fi

  require_privilege "installing ${check_cmd} via apt" || return 1

  if [ "$DRY_RUN" -eq 1 ]; then
    skip_action "Would install ${check_cmd} from ${repo}"
    return
  fi

  local url
  url="$(github_asset_url "$repo" "$regex")"
  if [ -z "$url" ]; then
    error "Could not find ${check_cmd} deb asset for ${repo}."
    return 1
  fi

  local tmpdir debfile
  tmpdir="$(mktemp -d)"
  debfile="$tmpdir/package.deb"

  if ! retry_with_backoff "Download ${check_cmd} deb" curl -fsSL "$url" -o "$debfile"; then
    rm -rf "$tmpdir"
    return 1
  fi

  ensure_apt_updated
  run_privileged env DEBIAN_FRONTEND=noninteractive apt-get "${APT_INSTALL_OPTS[@]}" install "$debfile"
  rm -rf "$tmpdir"
  mark_action_run
}

clone_if_missing() {
  local repo_url="$1"
  local target="$2"

  if [ -d "$target/.git" ]; then
    skip_action "Repository already present: $target"
    return
  fi

  if [ -e "$target" ]; then
    warn "Skipping clone; path exists and is not a git repo: $target"
    mark_action_skipped
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    skip_action "Would clone ${repo_url} to ${target}"
    return
  fi

  mkdir -p "$(dirname "$target")"
  retry_with_backoff "Cloning ${repo_url}" git clone --depth=1 "$repo_url" "$target"
  mark_action_run
}

install_oh_my_zsh() {
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      skip_action "Would install oh-my-zsh"
    else
      local installer
      installer="$(mktemp)"

      if ! retry_with_backoff "Download oh-my-zsh installer" curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$installer"; then
        rm -f "$installer"
        return 1
      fi

      if ! run_action "Installing oh-my-zsh" env RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh "$installer"; then
        rm -f "$installer"
        return 1
      fi

      rm -f "$installer"
    fi
  else
    skip_action "oh-my-zsh already installed"
  fi

  local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  clone_if_missing "https://github.com/romkatv/powerlevel10k.git" "$zsh_custom/themes/powerlevel10k"
  clone_if_missing "https://github.com/zsh-users/zsh-autosuggestions.git" "$zsh_custom/plugins/zsh-autosuggestions"
  clone_if_missing "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$zsh_custom/plugins/zsh-syntax-highlighting"
}

install_nvm_and_node() {
  export NVM_DIR="$HOME/.nvm"

  if [ "$DRY_RUN" -eq 1 ]; then
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
      skip_action "Would install nvm"
    else
      skip_action "nvm already installed"
    fi
    skip_action "Would ensure Node.js LTS via nvm"
    return
  fi

  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    local installer
    installer="$(mktemp)"

    if ! retry_with_backoff "Download nvm installer" curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh -o "$installer"; then
      rm -f "$installer"
      return 1
    fi

    if ! run_action "Installing nvm" bash "$installer"; then
      rm -f "$installer"
      return 1
    fi

    rm -f "$installer"
  else
    skip_action "nvm already installed"
  fi

  # shellcheck disable=SC1090
  . "$NVM_DIR/nvm.sh"

  local lts_version
  lts_version="$(nvm version "lts/*" 2>/dev/null || true)"
  if [ -z "$lts_version" ] || [ "$lts_version" = "N/A" ]; then
    retry_with_backoff "Installing Node.js LTS via nvm" nvm install --lts
    mark_action_run
  else
    skip_action "Node.js LTS already installed via nvm (${lts_version})"
  fi
  nvm alias default "lts/*" >/dev/null
  mark_action_run
  nvm use --silent default >/dev/null
}

install_uv() {
  if command -v uv >/dev/null 2>&1; then
    skip_action "uv already installed"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    skip_action "Would install uv"
    return
  fi

  local installer
  installer="$(mktemp)"

  if ! retry_with_backoff "Download uv installer" curl -LsSf https://astral.sh/uv/install.sh -o "$installer"; then
    rm -f "$installer"
    return 1
  fi

  if ! run_action "Installing uv" sh "$installer"; then
    rm -f "$installer"
    return 1
  fi

  rm -f "$installer"
}

install_go() {
  if command -v go >/dev/null 2>&1; then
    skip_action "go already installed"
    return
  fi

  if [ "$IS_LINUX" -ne 1 ]; then
    warn "Skipping Go install on unsupported OS: ${OS_NAME}."
    mark_action_skipped
    return
  fi

  if [ "$ARCH_NAME" = "unknown" ]; then
    warn "Skipping Go install; unsupported architecture: ${ARCH_RAW}."
    mark_action_skipped
    return
  fi

  require_privilege "installing Go into /usr/local" || return 1

  if [ "$DRY_RUN" -eq 1 ]; then
    skip_action "Would install Go for ${ARCH_NAME}"
    return
  fi

  local version_text version archive_url tmpdir archive
  version_text="$(retry_with_backoff "Fetch latest Go version" curl -fsSL https://go.dev/VERSION?m=text)"
  version="$(printf '%s\n' "$version_text" | head -n1)"

  if [ -z "$version" ]; then
    error "Unable to determine latest Go version."
    return 1
  fi

  archive_url="https://go.dev/dl/${version}.linux-${ARCH_NAME}.tar.gz"
  tmpdir="$(mktemp -d)"
  archive="$tmpdir/go.tar.gz"

  if ! retry_with_backoff "Download Go archive" curl -fsSL "$archive_url" -o "$archive"; then
    rm -rf "$tmpdir"
    return 1
  fi

  run_privileged rm -rf /usr/local/go
  run_privileged tar -C /usr/local -xzf "$archive"
  run_privileged ln -sfn /usr/local/go/bin/go /usr/local/bin/go
  run_privileged ln -sfn /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  rm -rf "$tmpdir"

  export PATH="/usr/local/go/bin:$PATH"
  mark_action_run
}

install_npm_package_if_missing() {
  local binary="$1"
  local package="$2"

  if command -v "$binary" >/dev/null 2>&1; then
    skip_action "${binary} already installed"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    skip_action "Would install npm package ${package}"
    return
  fi

  retry_with_backoff "Installing ${package}" npm install -g "$package"
  mark_action_run
}

install_ai_clis() {
  if ! command -v npm >/dev/null 2>&1; then
    warn "npm not found; skipping AI CLI npm installs."
    mark_action_skipped
    return
  fi

  install_npm_package_if_missing "claude" "@anthropic-ai/claude-code"
  install_npm_package_if_missing "gemini" "@google/gemini-cli"
  install_npm_package_if_missing "copilot" "@github/copilot"
  install_npm_package_if_missing "codex" "@openai/codex"

  if command -v gh >/dev/null 2>&1; then
    if gh extension list 2>/dev/null | awk '{print $1}' | grep -qx "github/gh-copilot"; then
      skip_action "gh extension github/gh-copilot already installed"
    elif [ "$DRY_RUN" -eq 1 ]; then
      skip_action "Would install gh extension github/gh-copilot"
    elif retry_with_backoff "Installing gh extension github/gh-copilot" gh extension install github/gh-copilot; then
      mark_action_run
    else
      warn "Unable to install gh-copilot extension; continuing."
      mark_action_skipped
    fi
  else
    skip_action "gh not found; skipping gh-copilot extension install"
  fi
}

install_agent_skills() {
  if ! command -v npx >/dev/null 2>&1; then
    warn "npx not found; skipping skills install."
    mark_action_skipped
    return
  fi

  local -a agent_args=()
  command -v claude >/dev/null 2>&1 && agent_args+=(-a claude-code)
  command -v codex >/dev/null 2>&1 && agent_args+=(-a codex)
  command -v gemini >/dev/null 2>&1 && agent_args+=(-a gemini-cli)
  command -v copilot >/dev/null 2>&1 && agent_args+=(-a github-copilot)

  if [ "${#agent_args[@]}" -eq 0 ]; then
    warn "No supported AI CLIs found; skipping skills install."
    mark_action_skipped
    return
  fi

  local -a skill_args=(
    -s add-badges
    -s agent-conventions
    -s email-whiz
    -s frontend-designer
    -s honest-review
    -s host-panel
    -s javascript-conventions
    -s learn
    -s mcp-creator
    -s orchestrator
    -s prompt-engineer
    -s python-conventions
    -s research
    -s skill-creator
  )

  local guard_dir="$HOME/.local/state"
  local guard_file="$guard_dir/dotfiles-agent-skills-v1"
  local guard_token existing_guard
  guard_token="$(printf '%s\n' "${skill_args[@]}" "${agent_args[@]}")"

  if [ -f "$guard_file" ]; then
    existing_guard="$(cat "$guard_file")"
    if [ "$existing_guard" = "$guard_token" ]; then
      skip_action "Agent skills already up to date"
      return
    fi
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    skip_action "Would install/update agent skills"
    return
  fi

  local attempt=1
  local delay="$NETWORK_RETRY_BASE_DELAY"
  local rc=1
  local install_output=""

  while [ "$attempt" -le "$NETWORK_RETRY_ATTEMPTS" ]; do
    debug "Attempt ${attempt}/${NETWORK_RETRY_ATTEMPTS}: Installing agent skills"
    if install_output="$(run_with_timeout npx -y skills add wyattowalsh/agents "${skill_args[@]}" "${agent_args[@]}" -g 2>&1)"; then
      mkdir -p "$guard_dir"
      printf '%s' "$guard_token" > "$guard_file"
      mark_action_run
      return
    fi

    rc=$?
    if is_network_or_auth_error "$install_output"; then
      warn "Skills install skipped due to network/auth constraints."
      printf '%s\n' "$install_output" >&2
      mark_action_skipped
      return
    fi

    if [ "$attempt" -lt "$NETWORK_RETRY_ATTEMPTS" ]; then
      warn "Skills install failed (attempt ${attempt}/${NETWORK_RETRY_ATTEMPTS}); retrying in ${delay}s."
      sleep "$delay"
      delay=$((delay * 2))
    fi

    attempt=$((attempt + 1))
  done

  printf '%s\n' "$install_output" >&2
  return "$rc"
}

link_file() {
  local source="$1"
  local target="$2"

  if [ ! -e "$source" ]; then
    warn "Skipping missing source: $source"
    mark_action_skipped
    return
  fi

  local target_dir
  target_dir="$(dirname "$target")"
  if [ ! -d "$target_dir" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      skip_action "Would create directory ${target_dir}"
    else
      mkdir -p "$target_dir"
      mark_action_run
    fi
  fi

  if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    skip_action "$target already links to $source"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    skip_action "Would link $target -> $source"
    return
  fi

  if [ -e "$target" ] && [ ! -L "$target" ]; then
    warn "Replacing existing path with symlink: $target"
  fi

  ln -sfn "$source" "$target"
  mark_action_run
}

sync_universal_skill_links() {
  local source_dir="$HOME/.agents/skills"
  if [ ! -d "$source_dir" ]; then
    skip_action "Universal skills source directory not found: $source_dir"
    return
  fi

  local -a target_dirs=()
  command -v copilot >/dev/null 2>&1 && target_dirs+=("$HOME/.copilot/skills")
  command -v codex >/dev/null 2>&1 && target_dirs+=("$HOME/.codex/skills")
  command -v gemini >/dev/null 2>&1 && target_dirs+=("$HOME/.gemini/skills")

  if [ "${#target_dirs[@]}" -eq 0 ]; then
    skip_action "No supported CLI skills directories found"
    return
  fi

  local target_dir skill_dir skill_name target_path
  for target_dir in "${target_dirs[@]}"; do
    if [ ! -d "$target_dir" ]; then
      if [ "$DRY_RUN" -eq 1 ]; then
        skip_action "Would create directory $target_dir"
      else
        mkdir -p "$target_dir"
        mark_action_run
      fi
    fi

    for skill_dir in "$source_dir"/*; do
      [ -d "$skill_dir" ] || continue
      skill_name="$(basename "$skill_dir")"
      target_path="$target_dir/$skill_name"

      if [ -e "$target_path" ] && [ ! -L "$target_path" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          skip_action "Would replace non-symlink path at $target_path"
        else
          rm -rf "$target_path"
          mark_action_run
        fi
      fi

      link_file "$skill_dir" "$target_path"
    done
  done
}

install_agents() {
  local target="$HOME/dev/tools/agents"

  if [ -d "$target/.git" ]; then
    skip_action "agents repository already present: $target"
  elif [ -e "$target" ]; then
    warn "Skipping agents clone; path exists and is not a git repo: $target"
    mark_action_skipped
  elif [ "$DRY_RUN" -eq 1 ]; then
    skip_action "Would clone agents repository into $target"
  else
    mkdir -p "$(dirname "$target")"
    retry_with_backoff "Cloning agents repository" git clone https://github.com/wyattowalsh/agents.git "$target"
    mark_action_run
  fi

  if command -v uv >/dev/null 2>&1 && ! command -v wagents >/dev/null 2>&1; then
    if [ "$DRY_RUN" -eq 1 ]; then
      skip_action "Would install wagents via uv"
    else
      retry_with_backoff "Installing wagents" uv tool install wagents
      mark_action_run
    fi
  elif command -v wagents >/dev/null 2>&1; then
    skip_action "wagents already installed"
  fi
}

create_symlinks() {
  link_file "$REPO_DIR/.zshrc" "$HOME/.zshrc"
  link_file "$REPO_DIR/.p10k.zsh" "$HOME/.p10k.zsh"
  link_file "$REPO_DIR/.gitconfig" "$HOME/.gitconfig"
  link_file "$REPO_DIR/.ripgreprc" "$HOME/.ripgreprc"
  link_file "$REPO_DIR/.editorconfig" "$HOME/.editorconfig"
  link_file "$REPO_DIR/.copilot/lsp-config.json" "$HOME/.copilot/lsp-config.json"
  link_file "$REPO_DIR/.copilot/mcp-config.json" "$HOME/.copilot/mcp-config.json"
  link_file "$REPO_DIR/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  link_file "$REPO_DIR/.config/claude/mcp.json" "$HOME/.config/claude/mcp.json"
}

set_zsh_default_shell() {
  if ! command -v zsh >/dev/null 2>&1 || ! command -v chsh >/dev/null 2>&1; then
    skip_action "zsh/chsh not available; skipping default shell update"
    return
  fi

  local zsh_path
  zsh_path="$(command -v zsh)"

  if [ "${SHELL:-}" = "$zsh_path" ]; then
    skip_action "Default shell already set to zsh"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    skip_action "Would set default shell to $zsh_path"
    return
  fi

  if chsh -s "$zsh_path" "${USER:-$(id -un)}"; then
    mark_action_run
  else
    warn "Unable to change default shell automatically. Run: chsh -s $zsh_path"
    mark_action_skipped
  fi
}

install_github_release_tools() {
  if [ "$IS_LINUX" -ne 1 ]; then
    warn "Skipping GitHub release tool installs on unsupported OS: ${OS_NAME}."
    mark_action_skipped
    return
  fi

  if [ "$ARCH_NAME" = "unknown" ]; then
    warn "Skipping GitHub release tool installs; unsupported architecture: ${ARCH_RAW}."
    mark_action_skipped
    return
  fi

  local eza_regex lazygit_regex zoxide_regex yazi_regex
  case "$ARCH_NAME" in
    amd64)
      eza_regex='eza_x86_64-unknown-linux-gnu\.tar\.gz$'
      lazygit_regex='lazygit_.*_linux_x86_64\.tar\.gz$'
      zoxide_regex='zoxide_.*_amd64\.deb$'
      yazi_regex='yazi-x86_64-unknown-linux-gnu\.deb$'
      ;;
    arm64)
      eza_regex='eza_aarch64-unknown-linux-gnu\.tar\.gz$'
      lazygit_regex='lazygit_.*_linux_arm64\.tar\.gz$'
      zoxide_regex='zoxide_.*_arm64\.deb$'
      yazi_regex='yazi-aarch64-unknown-linux-gnu\.deb$'
      ;;
  esac

  install_tar_binary_from_github "eza-community/eza" "$eza_regex" "eza"
  install_tar_binary_from_github "jesseduffield/lazygit" "$lazygit_regex" "lazygit"
  install_deb_from_github "ajeetdsouza/zoxide" "$zoxide_regex" "zoxide"
  install_deb_from_github "sxyazi/yazi" "$yazi_regex" "yazi"
}

main() {
  parse_args "$@"
  detect_platform
  run_preflight_checks

  if [ "$SMOKE_CHECK" -eq 1 ]; then
    run_smoke_checks
    return
  fi

  if [ "$DRY_RUN" -eq 0 ]; then
    acquire_setup_lock
  else
    info "Dry-run mode enabled; mutation lock acquisition skipped."
  fi

  ensure_local_bin
  install_apt_tools
  install_oh_my_zsh
  install_github_release_tools
  install_nvm_and_node
  install_uv
  install_go
  install_ai_clis
  install_agent_skills
  sync_universal_skill_links
  install_agents
  create_symlinks
  set_zsh_default_shell

  if [ "$VERBOSE" -eq 1 ]; then
    run_smoke_checks || warn "Post-run smoke checks reported issues."
  fi
}

trap cleanup EXIT
main "$@"
