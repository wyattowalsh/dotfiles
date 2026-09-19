#!/usr/bin/env bash
# Static contract for the opt-in RustDesk-over-Tailscale runner.
# No live launchctl, brew, TCC, or power writes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/rig/home/dot_local/bin/executable_remote-access"
JUSTFILE="$ROOT/justfile"
DOCS="$ROOT/docs/content/docs/remote-access.mdx"
BOOTSTRAP="$ROOT/rig/bootstrap/macos.sh"
ZSHRC="$ROOT/rig/dots/zshrc"
FIXTURE_TOML="$ROOT/checks/fixtures/remote-access/RustDesk2.toml"
BATS="$ROOT/checks/remote-access.bats"

fail=0

fail_msg() {
  printf 'remote-access: %s\n' "$*" >&2
  fail=1
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    fail_msg "missing $path"
    return 1
  fi
  return 0
}

require_file "$RUNNER" || true
require_file "$JUSTFILE" || true
require_file "$DOCS" || true
require_file "$BOOTSTRAP" || true
require_file "$ZSHRC" || true
require_file "$FIXTURE_TOML" || true
require_file "$BATS" || true

if [[ -f "$RUNNER" ]]; then
  if [[ ! -s "$RUNNER" ]]; then
    fail_msg "runner is empty (restore from live dest or the last good copy)"
  fi
  if ! head -n 1 "$RUNNER" | grep -q '^#!/usr/bin/env bash$'; then
    fail_msg "runner must start with #!/usr/bin/env bash"
  fi
  if ! grep -q 'set -euo pipefail' "$RUNNER"; then
    fail_msg "runner must set -euo pipefail"
  fi
  if grep -q '/Users/' "$RUNNER"; then
    fail_msg "runner must not hardcode /Users/ paths"
  fi
  if ! grep -q 'password flags are refused' "$RUNNER"; then
    fail_msg "runner must refuse --password argv"
  fi
  if ! grep -q 'password environment variables are refused' "$RUNNER"; then
    fail_msg "runner must refuse password environment variables"
  fi
  if ! grep -q 'cannot be used together' "$RUNNER"; then
    fail_msg "runner must reject --dry-run combined with --apply"
  fi
  if ! grep -q 'another remote-access process' "$RUNNER"; then
    fail_msg "runner must report lock contention"
  fi
  if ! grep -q 'com.carriez.RustDesk_service' "$RUNNER"; then
    fail_msg "runner must install vendor daemon label com.carriez.RustDesk_service"
  fi
  if ! grep -q 'com.carriez.RustDesk_server' "$RUNNER"; then
    fail_msg "runner must install vendor agent label com.carriez.RustDesk_server"
  fi
  if ! grep -q 'refusing allow-all' "$RUNNER"; then
    fail_msg "runner must refuse an empty/allow-all whitelist"
  fi
  if ! grep -q 'would not set or rotate a password' "$RUNNER"; then
    fail_msg "enable --dry-run must promise not to set or rotate a password"
  fi
  if ! grep -q 'preserving GUI Tailscale' "$RUNNER"; then
    fail_msg "runner must preserve an existing GUI Tailscale.app"
  fi
  if ! grep -q 'intent remains disabled' "$RUNNER"; then
    fail_msg "install must not re-enable after disable"
  fi
  if ! grep -q 'unsupported on' "$RUNNER"; then
    fail_msg "mutating commands must reject non-Darwin with unsupported"
  fi
  if grep -Eq 'caffeinate|pmset' "$RUNNER"; then
    fail_msg "runner must not change power policy"
  fi
  if grep -Eq 'tailscale[[:space:]]+(up|down|logout)[[:space:]]+--reset' "$RUNNER"; then
    fail_msg "runner must not reset Tailscale identity"
  fi
fi

if [[ -f "$JUSTFILE" ]]; then
  # shellcheck disable=SC2016 # literal dest-runner snippet; must not expand
  if grep -F -q 'exec "${HOME}/.local/bin/remote-access"' "$JUSTFILE"; then
    fail_msg "justfile must not exec dest runner"
  fi
  if ! grep -q 'REMOTE_ACCESS_REPO' "$JUSTFILE"; then
    fail_msg "justfile remote-access recipe must export REMOTE_ACCESS_REPO"
  fi
  if ! grep -q 'justfile_directory' "$JUSTFILE"; then
    fail_msg "justfile recipes must use justfile_directory"
  fi
  if ! grep -q 'check-remote-access' "$JUSTFILE"; then
    fail_msg "justfile must expose check-remote-access"
  fi
  if ! grep -q 'checks/remote-access.sh' "$JUSTFILE"; then
    fail_msg "justfile shell_files or check recipe must include checks/remote-access.sh"
  fi
fi

if [[ -f "$BOOTSTRAP" ]]; then
  if ! grep -q 'with-remote-access' "$BOOTSTRAP"; then
    fail_msg "macos.sh must opt in with --with-remote-access"
  fi
  if grep -q 'enable --apply' "$BOOTSTRAP"; then
    fail_msg "macos.sh must not call enable --apply"
  fi
fi

if [[ -f "$ZSHRC" ]]; then
  if grep -E -q 'tailscaled|RustDesk|--server' "$ZSHRC"; then
    fail_msg "zshrc must not start rustdesk/tailscaled"
  fi
fi

if [[ -f "$DOCS" ]]; then
  if ! grep -q 'just remote-access' "$DOCS"; then
    fail_msg "docs must document just remote-access"
  fi
  if ! grep -q 'never auto-enabled' "$DOCS" && ! grep -q 'never auto-enable' "$DOCS"; then
    fail_msg "docs must say unattended access is never auto-enabled"
  fi
fi

if [[ -f "$FIXTURE_TOML" ]]; then
  if ! grep -Fq "keep-me = 'yes'" "$FIXTURE_TOML"; then
    fail_msg "fixture RustDesk2.toml must preserve keep-me for merge tests"
  fi
  if grep -Ei '^[[:space:]]*password[[:space:]]*=' "$FIXTURE_TOML"; then
    fail_msg "options fixture must not contain a password"
  fi
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

printf 'remote-access: ok\n'
