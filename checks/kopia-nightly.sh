#!/usr/bin/env bash
# Static contract for the headless Kopia nightly runner (no kopia/launchctl).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/rig/home/dot_local/bin/executable_kopia-nightly"
PLIST="$ROOT/rig/home/Library/LaunchAgents/com.wyattowalsh.kopia-nightly.plist.tmpl"
JUSTFILE="$ROOT/justfile"

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
  if ! rg -q 'Logs/kopia/tmp' "$RUNNER"; then
    fail_msg "runner must create Logs/kopia/tmp"
  fi
  if ! rg -q 'trap ' "$RUNNER"; then
    fail_msg "runner must trap EXIT/TERM so login agents still disable"
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
  if ! rg -q '<integer>43200</integer>' "$PLIST"; then
    fail_msg "plist TimeOut must be 43200"
  fi
  if rg -q '<integer>21600</integer>' "$PLIST"; then
    fail_msg "plist must not keep the old 21600 TimeOut"
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

printf 'kopia-nightly: ok\n'
