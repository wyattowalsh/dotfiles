#!/usr/bin/env bash
# Static contract for Spotify pin + Spicetify apply (no live Spotify/launchctl).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/rig/home/dot_local/bin/executable_spicetify-apply"
PLIST="$ROOT/rig/home/Library/LaunchAgents/com.wyattowalsh.spicetify-apply.plist.tmpl"
PIN="$ROOT/rig/brew/spotify-pin.json"
SKIP="$ROOT/rig/home/private_dot_config/freshen/skip-casks"
JUSTFILE="$ROOT/justfile"
DOCS="$ROOT/docs/content/docs/spotify.mdx"
ZSHRC="$ROOT/rig/dots/zshrc"
MACOS="$ROOT/rig/bootstrap/macos.sh"

fail=0

fail_msg() {
  printf 'spicetify: %s\n' "$*" >&2
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
require_file "$PIN" || true
require_file "$SKIP" || true
require_file "$JUSTFILE" || true
require_file "$DOCS" || true
require_file "$ZSHRC" || true

if [[ -f "$JUSTFILE" ]]; then
  if rg -q 'if \[\[ -x "\$\{HOME\}/\.local/bin/spicetify-apply" \]\]' "$JUSTFILE"; then
    fail_msg "justfile must not dest-first exec the home runner"
  fi
  if rg -F -q 'exec "${HOME}/.local/bin/spicetify-apply"' "$JUSTFILE"; then
    fail_msg "justfile must not exec dest runner"
  fi
  if ! rg -q 'SPICETIFY_REPO' "$JUSTFILE"; then
    fail_msg "justfile install recipe must export SPICETIFY_REPO"
  fi
fi

if [[ -f "$RUNNER" ]]; then
  if ! head -n 1 "$RUNNER" | rg -q '^#!/usr/bin/env bash$'; then
    fail_msg "runner must start with #!/usr/bin/env bash"
  fi
  if ! rg -q 'set -euo pipefail' "$RUNNER"; then
    fail_msg "runner must set -euo pipefail"
  fi
  if rg -q '/Users/' "$RUNNER"; then
    fail_msg "runner must not hardcode /Users/ paths"
  fi
  if ! rg -q 'chflags uchg' "$RUNNER"; then
    fail_msg "runner must block Spotify updates with uchg"
  fi
  if ! rg -q 'backup apply' "$RUNNER"; then
    fail_msg "runner must run spicetify backup apply"
  fi
  if ! rg -q 'stale backup' "$RUNNER"; then
    fail_msg "runner must rebuild backup from a vanilla pin on mismatch"
  fi
  if ! rg -q '/opt/homebrew/bin/spicetify' "$RUNNER"; then
    fail_msg "runner must prefer Homebrew spicetify"
  fi
  if rg -q 'spicetify auto' "$RUNNER"; then
    fail_msg "runner must not launch Spotify via spicetify auto"
  fi
  if rg -q 'flock -n' "$RUNNER"; then
    fail_msg "apply lock must wait, not skip"
  fi
  if ! rg -q 'plist.tmpl' "$RUNNER"; then
    fail_msg "install must render dest plist from tmpl"
  fi
  if ! rg -q 'skip-casks' "$RUNNER"; then
    fail_msg "install must ensure freshen skip-casks"
  fi
fi

if [[ -f "$PLIST" ]]; then
  if ! rg -q 'WatchPaths' "$PLIST"; then
    fail_msg "plist must WatchPaths Spotify.app"
  fi
  if ! rg -q '/Applications/Spotify.app' "$PLIST"; then
    fail_msg "plist must watch /Applications/Spotify.app"
  fi
  if ! rg -q '<string>apply</string>' "$PLIST"; then
    fail_msg "plist must invoke apply subcommand"
  fi
  if ! rg -q 'chezmoi.homeDir' "$PLIST"; then
    fail_msg "plist must template paths with chezmoi.homeDir"
  fi
  if rg -q '/Users/' "$PLIST"; then
    fail_msg "plist must not hardcode /Users/ paths"
  fi
  if ! rg -q '/opt/homebrew/bin' "$PLIST"; then
    fail_msg "plist PATH must prefer Homebrew"
  fi
fi

if [[ -f "$PIN" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    if ! python3 - "$PIN" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except json.JSONDecodeError as exc:
    print(f"invalid json: {exc}", file=sys.stderr)
    raise SystemExit(1)

errors = []
for key in ("spicetify_cli", "spotify_supported_max", "spotify_pin", "spotify_fullversion"):
    if not str(data.get(key) or "").strip():
        errors.append(f"{key} must be present")
arm = data.get("darwin_arm64") or {}
if not isinstance(arm, dict):
    errors.append("darwin_arm64 must be an object")
else:
    url = str(arm.get("url") or "")
    if "loadspot" not in url and "scdn.co" not in url:
        errors.append("darwin_arm64.url must be a versioned LoaderSpot or Spotify CDN URL")
    if "SpotifyARM64.dmg" in url or url.endswith("/Spotify.dmg"):
        errors.append("darwin_arm64.url must not be the unversioned Homebrew DMG")
    if not str(arm.get("sha256") or "").strip():
        errors.append("darwin_arm64.sha256 must be present")
    try:
        size = int(arm.get("size") or 0)
    except (TypeError, ValueError):
        size = 0
    if size <= 0:
        errors.append("darwin_arm64.size must be a positive int")
if errors:
    print("; ".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
    then
      fail_msg "spotify-pin.json schema check failed"
    fi
  elif command -v jq >/dev/null 2>&1; then
    jq empty "$PIN" >/dev/null || fail_msg "spotify-pin.json is not valid JSON"
  fi
fi

if [[ -f "$SKIP" ]]; then
  if ! rg -qx 'spotify' "$SKIP"; then
    fail_msg "freshen skip-casks must list spotify"
  fi
fi

if [[ -f "$ZSHRC" ]]; then
  if rg -q '\$HOME/\.spicetify' "$ZSHRC"; then
    fail_msg "zshrc must not put ~/.spicetify ahead of Homebrew on PATH"
  fi
fi

if [[ -f "$DOCS" ]]; then
  if ! rg -q 'just spicetify' "$DOCS"; then
    fail_msg "spotify.mdx must document just spicetify"
  fi
  if rg -q '/Users/' "$DOCS"; then
    fail_msg "spotify.mdx must not hardcode /Users/ paths"
  fi
fi

if [[ -f "$MACOS" ]]; then
  python3 - "$MACOS" <<'PY' || fail_msg "macos.sh must pin Spotify before installing the LaunchAgent"
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
apply_at = text.find("Pin Spotify and apply Spicetify")
install_at = text.find("Install Spicetify apply LaunchAgent")
if apply_at < 0 or install_at < 0 or apply_at > install_at:
    raise SystemExit(1)
PY
fi

if [[ "$fail" -ne 0 ]]; then
  printf 'spicetify: FAIL\n' >&2
  exit 1
fi

printf 'spicetify: ok\n'
