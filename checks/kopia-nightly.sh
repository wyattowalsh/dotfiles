#!/usr/bin/env bash
# Static contract for the headless Kopia nightly runner (no kopia/launchctl).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/rig/home/dot_local/bin/executable_kopia-nightly"
PLIST="$ROOT/rig/home/Library/LaunchAgents/com.wyattowalsh.kopia-nightly.plist.tmpl"
JUSTFILE="$ROOT/justfile"
DOCS="$ROOT/docs/content/docs/backup.mdx"

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
require_file "$DOCS" || true

check_policy_fixtures() (
  fixture_dir="$(mktemp -d)" || exit 1
  trap 'rm -rf -- "$fixture_dir"' EXIT
  export HOME="$fixture_dir/home"
  # Source the functions without calling main, then stub the sole provider call.
  # shellcheck source=/dev/null
  source <(sed '/^main "\$@"$/d' "$RUNNER") || exit 1
  # shellcheck disable=SC2329 # Called by the sourced doctor function.
  run_timeout() { cat "$policy_fixture"; }
  mkdir -p "$TMP_DIR" || exit 1
  source_list >"$fixture_dir/sources" || exit 1
  archive="$HOME/.local/share/mba-phone-usb-successor/archive-20261025-v123"
  python3 - "$fixture_dir" "$archive" <<'PY' || exit 1
import json
import os
import sys
from pathlib import Path

directory = Path(sys.argv[1])
archive = sys.argv[2]
sources = (directory / "sources").read_text().splitlines()
assert len(sources) == len(set(sources)) == 15 and archive in sources

def row(path):
    return {"target": {"path": path}, "scheduling": {"timeOfDay": [{"hour": 4, "min": 0}]}}

home = os.environ["HOME"]
valid = [row(path) for path in sources if path != archive] + [row(home)]
for case, rows in {
    "valid": valid,
    "missing": [entry for entry in valid if entry["target"]["path"] != home + "/Documents"],
    "extra": valid + [row(home + "/unexpected")],
    "archive": valid + [row(archive)],
}.items():
    (directory / case).write_text(json.dumps(rows))
PY
  policy_fixture="$fixture_dir/valid"
  output="$(doctor_policies)" && [[ "$output" == *"launchd-only source ok: $archive"* ]] || exit 1
  policy_fixture="$fixture_dir/missing"
  ! output="$(doctor_policies)" && [[ "$output" == *"policy 04:00 missing or unread: $HOME/Documents"* ]] || exit 1
  policy_fixture="$fixture_dir/extra"
  ! output="$(doctor_policies)" && [[ "$output" == *"extra 04:00 source not in script list: $HOME/unexpected"* ]] || exit 1
  policy_fixture="$fixture_dir/archive"
  ! output="$(doctor_policies)" && [[ "$output" == *"unexpected 04:00 policy for launchd-only source: $archive"* ]]
)

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
  if ! rg -q 'KOPIA_NIGHTLY_TIMEOUT_SEC' "$RUNNER"; then
    fail_msg "runner must honor KOPIA_NIGHTLY_TIMEOUT_SEC"
  fi
  if ! rg -q 'gtimeout' "$RUNNER"; then
    fail_msg "runner must fall back to gtimeout"
  fi
  if ! rg -q -e 'command timeout' -e 'command -v timeout' "$RUNNER"; then
    fail_msg "runner must invoke timeout/gtimeout for the wall-clock cap"
  fi

  if ! rg -q '^umask 077$' "$RUNNER"; then
    fail_msg "runner must create private runtime files by default"
  fi
  runtime_body="$(awk '/^runtime_paths\(\)/,/^}/' "$RUNNER")"
  # shellcheck disable=SC2016 # These are literal runner-source fragments.
  for marker in \
    '[[ -L "$path" ]]' '! -O "$path"' 'mkdir -m 700 "$path"' \
    '8#$mode & 0022' '[[ "$mode" != 700 ]]' '[[ "$mode" != 600 ]]' 'set -o noclobber' \
    'nightly.lock' 'nightly.out.log' 'nightly.err.log'; do
    if ! rg -F -q -- "$marker" <<<"$runtime_body"; then
      fail_msg "runtime guard missing: $marker"
    fi
  done
  if rg -q 'chmod|chown|rm -' <<<"$runtime_body"; then
    fail_msg "runtime guard must not repair existing paths"
  fi

  run_body="$(awk '/^cmd_bounded_run\(\)/,/^}/' "$RUNNER")"
  # shellcheck disable=SC2016 # Compare source text without expanding its variables.
  for marker in 'runtime_paths 1' 'export TMPDIR="${TMP_DIR}"' 'exec 9>>"${LOG_DIR}/nightly.lock"'; do
    if ! rg -F -q -- "$marker" <<<"$run_body"; then
      fail_msg "snapshot startup missing: $marker"
    fi
  done
  install_body="$(awk '/^cmd_install\(\)/,/^}/' "$RUNNER")"
  if ! rg -F -q 'runtime_paths 1' <<<"$install_body"; then
    fail_msg "install must prepare private log/TMPDIR entries before bootstrap"
  fi
  if ! awk '
    /runtime_paths 1/ { ready=1 }
    /^[[:space:]]*\/bin\/cp -f/ && !ready { bad=1 }
    /^[[:space:]]*ensure_login_disabled/ && !ready { bad=1 }
    END { exit bad ? 1 : 0 }
  ' <<<"$install_body"; then
    fail_msg "install must guard runtime paths before runner sync or scheduler mutations"
  fi
  if rg -q 'launchctl (kickstart|start)' "$RUNNER"; then
    fail_msg "install/doctor must not start an immediate snapshot"
  fi

  doctor_body="$(awk '/^cmd_doctor\(\)/,/^}/' "$RUNNER")"
  # shellcheck disable=SC2016 # Compare source text without expanding its variables.
  for marker in \
    'runtime_paths 0' 'run_timeout 125 env -i' \
    'TMPDIR="${TMP_DIR}" kopia repository status >/dev/null 2>&1' \
    'cause UNKNOWN' 'saved-auth/keyring' 'raw diagnostics suppressed' \
    '[[ "$repository_ready" -eq 1 ]]' 'dest runner: missing'; do
    if ! rg -F -q -- "$marker" <<<"$doctor_body"; then
      fail_msg "read-only bounded doctor missing: $marker"
    fi
  done
  if rg -q 'runtime_paths 1|mkdir|chmod|ensure_kopiaui_quit|ensure_login_disabled|snapshot create' <<<"$doctor_body"; then
    fail_msg "doctor must not repair runtime paths, quit the GUI, change schedulers or upload"
  fi
  if rg -q 'cannot see repo' <<<"$doctor_body"; then
    fail_msg "a status failure must not be presented as a diagnosed repository/auth cause"
  fi
  policies_body="$(awk '/^doctor_policies\(\)/,/^}/' "$RUNNER")"
  if ! rg -F -q 'run_timeout 90 env -i' <<<"$policies_body" \
    || ! rg -F -q 'mktemp "${TMP_DIR}/policies.XXXXXX"' <<<"$policies_body"; then
    fail_msg "optional policy probe must be bounded and use private temporary storage"
  fi
  check_policy_fixtures || fail_msg "04:00 policy catalog fixtures failed"

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
  for suffix in 'tmp' 'nightly.out.log' 'nightly.err.log'; do
    if ! rg -F -q "<string>{{ .chezmoi.homeDir }}/Library/Logs/kopia/${suffix}</string>" "$PLIST"; then
      fail_msg "plist runtime paths must match guarded runner entries: $suffix"
    fi
  done
  if rg -q '<key>TimeOut</key>' "$PLIST"; then
    fail_msg "plist must not set unimplemented TimeOut (runner enforces the cap)"
  fi
  if rg -q '/Users/' "$PLIST"; then
    fail_msg "plist must not hardcode /Users/ paths"
  fi
  if rg -qi 'drive-root-folder-id|KOPIA_PASSWORD' "$PLIST"; then
    fail_msg "plist must not embed secrets"
  fi
fi

if [[ -f "$DOCS" ]]; then
  if rg -qi 'sigterm' "$DOCS"; then
    fail_msg "backup.mdx must not claim launchd SIGTERM (cap is in the runner)"
  fi
  if rg -qi 'timeout after 12 hours' "$DOCS"; then
    fail_msg "backup.mdx must not treat launchd TimeOut as a 12h kill"
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
