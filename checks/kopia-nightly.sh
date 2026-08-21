#!/usr/bin/env bash
# Static contract for the headless Kopia nightly runner (no kopia/launchctl).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/rig/home/dot_local/bin/executable_kopia-nightly"
PLIST="$ROOT/rig/home/Library/LaunchAgents/com.wyattowalsh.kopia-nightly.plist.tmpl"
JUSTFILE="$ROOT/justfile"
FIXTURES="$ROOT/checks/kopia-nightly-fixtures.sh"

fail=0

fail_msg() {
  printf 'kopia-nightly: %s\n' "$*" >&2
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
require_file "$PLIST" || true
require_file "$JUSTFILE" || true
require_file "$FIXTURES" || true

if [[ -f "$JUSTFILE" ]]; then
  if rg -q 'if \[\[ -x "\$\{HOME\}/\.local/bin/kopia-nightly" \]\]' "$JUSTFILE"; then
    fail_msg "justfile must not dest-first exec the home runner"
  fi
  if rg -F -q 'exec "${HOME}/.local/bin/kopia-nightly"' "$JUSTFILE"; then
    fail_msg "justfile must not exec dest runner"
  fi
  if ! rg -q 'justfile_directory' "$JUSTFILE"; then
    fail_msg "justfile kopia recipes must use justfile_directory"
  fi
  if ! rg -q 'KOPIA_NIGHTLY_REPO' "$JUSTFILE"; then
    fail_msg "justfile install recipe must export KOPIA_NIGHTLY_REPO"
  fi
fi

if [[ -f "$RUNNER" ]]; then
  if ! head -n 1 "$RUNNER" | rg -q '^#!/usr/bin/env bash$'; then
    fail_msg "runner must start with #!/usr/bin/env bash"
  fi
  if ! rg -q 'set -euo pipefail' "$RUNNER"; then
    fail_msg "runner must set -euo pipefail"
  fi
  if rg -q -- '--all' "$RUNNER"; then
    fail_msg "runner must not mention --all"
  fi
  if rg -q '/Users/' "$RUNNER"; then
    fail_msg "runner must not hardcode /Users/ paths"
  fi
  if rg -qi 'drive-root-folder-id|KOPIA_PASSWORD' "$RUNNER"; then
    fail_msg "runner must not embed repo secrets or passwords"
  fi
  if ! rg -q 'caffeinate' "$RUNNER"; then
    fail_msg "runner must hold idle sleep with caffeinate"
  fi
  if rg -q 'kill .*caffein|caffeine_pid' "$RUNNER"; then
    fail_msg "runner must let caffeinate -w follow the runner instead of killing a stored PID"
  fi
  if ! rg -q 'Logs/kopia/tmp' "$RUNNER"; then
    fail_msg "runner must create Logs/kopia/tmp"
  fi
  if ! rg -F -q 'RUN_TIMEOUT_SECONDS=43140' "$RUNNER" \
    || ! rg -F -q 'RUN_KILL_GRACE_SECONDS=60' "$RUNNER" \
    || ! rg -F -q '"$GTIMEOUT" --verbose --signal=TERM --kill-after="${RUN_KILL_GRACE_SECONDS}s" "${RUN_TIMEOUT_SECONDS}s" "$0" __bounded-run' "$RUNNER"; then
    fail_msg "normal runs must use the fixed 43140s + 60s external gtimeout wrapper"
  fi
  if ! rg -F -q '"$GTIMEOUT" --signal=TERM --kill-after=5s 30s kopia repository status >/dev/null 2>&1' "$RUNNER"; then
    fail_msg "repository status must be quiet and bounded to 30s TERM + 5s KILL grace"
  fi
  if ! rg -F -q 'local max_attempts=8' "$RUNNER" \
    || ! rg -F -q 'local -a delays=(5 10 20 30 30 30 30)' "$RUNNER"; then
    fail_msg "repository readiness must use eight attempts and the fixed backoff schedule"
  fi
  if ! rg -F -q 'flock -n 9' "$RUNNER"; then
    fail_msg "runner must retain the single-run flock"
  fi
  if ! rg -F -q '[[ -t 1 && -z "${XPC_SERVICE_NAME:-}" ]]' "$RUNNER"; then
    fail_msg "snapshot progress must remain gated off under launchd"
  fi
  if ! rg -F -q 'trap '\''finalize_run "$?"'\'' EXIT' "$RUNNER" \
    || ! rg -F -q 'trap '\''handle_signal 143'\'' TERM' "$RUNNER" \
    || ! rg -F -q 'trap '\''handle_signal 130'\'' INT' "$RUNNER"; then
    fail_msg "runner must use one EXIT finalizer and signal-specific TERM/INT handlers"
  fi
  if ! rg -F -q 'RUN_MAINTENANCE_WARNING=1' "$RUNNER"; then
    fail_msg "maintenance-only failure must be retained as a warning outcome"
  fi
  if ! rg -F -q 'RUN_NOTIFICATION_SENT=1' "$RUNNER" \
    || ! rg -F -q '10s osascript' "$RUNNER"; then
    fail_msg "runner must bound and de-duplicate outcome notification"
  fi
  if rg -q '/4:00/' "$RUNNER"; then
    fail_msg "runner must not use awk /4:00/ substring matching"
  fi

  expected_suffixes=(
    '.bash_profile'
    '.bashrc'
    '.codex/memories'
    '.gitconfig'
    '.github'
    '.gitignore'
    '.zshrc'
    'Documents'
    'Movies'
    'Music'
    'Pictures'
    'Public'
    'dev'
    'src'
  )
  for suffix in "${expected_suffixes[@]}"; do
    if ! rg -F -q "\${HOME}/${suffix}" "$RUNNER"; then
      fail_msg "runner missing source \${HOME}/${suffix}"
    fi
  done

  if awk '/^source_list\(\)/,/^}/ { if ($0 ~ /^[[:space:]]*"\$\{HOME\}"[[:space:]]*$/) found=1 } END { exit found ? 0 : 1 }' "$RUNNER"; then
    fail_msg "source_list must not snapshot the home directory itself"
  fi
fi

if [[ -f "$PLIST" ]]; then
  if ! rg -q 'StartCalendarInterval' "$PLIST"; then
    fail_msg "plist must set StartCalendarInterval"
  fi
  if ! rg -q '<key>Hour</key>' "$PLIST" || ! rg -q '<integer>4</integer>' "$PLIST"; then
    fail_msg "plist must schedule Hour 4"
  fi
  if ! rg -q '<key>Minute</key>' "$PLIST" || ! rg -q '<integer>0</integer>' "$PLIST"; then
    fail_msg "plist must schedule Minute 0"
  fi
  if ! rg -q '<key>RunAtLoad</key>' "$PLIST" || ! rg -A1 '<key>RunAtLoad</key>' "$PLIST" | rg -q '<false/>'; then
    fail_msg "plist RunAtLoad must be false"
  fi
  if ! rg -q 'chezmoi.homeDir' "$PLIST"; then
    fail_msg "plist must template paths with chezmoi.homeDir"
  fi
  if rg -q '<key>TimeOut</key>' "$PLIST"; then
    fail_msg "plist must not use launchd's unimplemented TimeOut key"
  fi
  if ! rg -q '<key>ExitTimeOut</key>' "$PLIST" \
    || ! rg -A1 '<key>ExitTimeOut</key>' "$PLIST" | rg -q '<integer>120</integer>'; then
    fail_msg "plist ExitTimeOut must provide 120 seconds of stop grace"
  fi
  if rg -q '/Users/' "$PLIST"; then
    fail_msg "plist must not hardcode /Users/ paths"
  fi
  if rg -qi 'drive-root-folder-id|KOPIA_PASSWORD' "$PLIST"; then
    fail_msg "plist must not embed secrets"
  fi
fi

while IFS= read -r tracked; do
  case "$tracked" in
    *repository.config* | *rclone.conf)
      fail_msg "must not track $tracked"
      ;;
  esac
done < <(git -C "$ROOT" ls-files)

if [[ "$fail" -ne 0 ]]; then
  printf 'kopia-nightly: FAIL\n' >&2
  exit 1
fi

"$FIXTURES"

printf 'kopia-nightly: ok\n'
