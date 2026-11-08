#!/usr/bin/env bash
# Static contract for music likes sync (runner + matcher + LaunchAgent + pin + docs; no live Spotify/Soulseek/launchctl/beets writes).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/rig/home/dot_local/bin/executable_music-likes"
MATCH="$ROOT/rig/home/dot_local/bin/executable_music-likes-match"
PLIST="$ROOT/rig/home/Library/LaunchAgents/com.wyattowalsh.music-likes.plist.tmpl"
PIN="$ROOT/rig/brew/sockseek-pin.json"
FIXTURES="$ROOT/checks/fixtures/music-likes"
NAVIDROME="$ROOT/rig/home/private_dot_config/navidrome/navidrome.toml.tmpl"
JUSTFILE="$ROOT/justfile"
DOCS="$ROOT/docs/content/docs/music.mdx"
MACOS="$ROOT/rig/bootstrap/macos.sh"
ENV_EXAMPLE="$ROOT/.env.example"
GITIGNORE="$ROOT/.gitignore"
BREW_AGENTS="$ROOT/rig/brew/AGENTS.md"

fail=0

fail_msg() {
  printf 'music-likes: %s\n' "$*" >&2
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

runner_without_manual_sockseek() {
  # Print the runner minus the manual cmd_sockseek() passthrough body so that
  # manual-only flags (spotify-likes, --skip-music-dir) can be forbidden on the
  # scheduled path while staying legal inside cmd_sockseek.
  awk '
    /^cmd_sockseek ?\(\)/ { infn = 1 }
    !infn { print }
    infn && /^}/ { infn = 0 }
  ' "$RUNNER"
}

require_file "$RUNNER" || true
require_file "$MATCH" || true
require_file "$PLIST" || true
require_file "$PIN" || true
require_file "$FIXTURES/liked.csv" || true
require_file "$FIXTURES/library.sql" || true
require_file "$FIXTURES/expected-missing.csv" || true
require_file "$FIXTURES/expected-liked-songs.m3u" || true
require_file "$NAVIDROME" || true
require_file "$JUSTFILE" || true
require_file "$DOCS" || true
require_file "$MACOS" || true
require_file "$ENV_EXAMPLE" || true
require_file "$GITIGNORE" || true
require_file "$BREW_AGENTS" || true

if [[ -f "$JUSTFILE" ]]; then
  if rg -q 'if \[\[ -x "\$\{HOME\}/\.local/bin/music-likes" \]\]' "$JUSTFILE"; then
    fail_msg "justfile must not dest-first exec the home likes runner"
  fi
  if rg -F -q 'exec "${HOME}/.local/bin/music-likes"' "$JUSTFILE"; then
    fail_msg "justfile must not exec the dest likes runner"
  fi
  if ! rg -F -q 'executable_music-likes' "$JUSTFILE"; then
    fail_msg "justfile must exec the repo runner for music-likes"
  fi
  if ! rg -F -q 'executable_music-likes" "$@"' "$JUSTFILE"; then
    fail_msg "just music-likes must quote args so paths with spaces work"
  fi
  if ! rg -q '\[positional-arguments\]' "$JUSTFILE"; then
    fail_msg "just music-likes must use [positional-arguments] so playlist paths keep spaces"
  fi
  if ! rg -q 'MUSIC_LIKES_REPO' "$JUSTFILE"; then
    fail_msg "justfile recipes must export MUSIC_LIKES_REPO"
  fi
  if ! rg -F -q 'check-music-likes' "$JUSTFILE"; then
    fail_msg "justfile must wire check-music-likes into the gate"
  fi
fi

if [[ -f "$RUNNER" ]]; then
  if ! head -n 1 "$RUNNER" | rg -q '^#!/usr/bin/env bash$'; then
    fail_msg "runner must start with #!/usr/bin/env bash"
  fi
  if ! rg -q 'set -euo pipefail' "$RUNNER"; then
    fail_msg "runner must set -euo pipefail"
  fi
  if ! rg -F -q 'flock -n' "$RUNNER"; then
    fail_msg "runner must flock -n so an overlapping tick exits instead of piling up"
  fi
  if ! rg -F -q 'already running' "$RUNNER"; then
    fail_msg "runner must log 'already running' when the lock is held"
  fi
  if ! rg -F -q 'sync.lock' "$RUNNER"; then
    fail_msg "runner must take the sync.lock lock file"
  fi
  if ! rg -F -q 'music-writer.lock' "$RUNNER" || ! rg -F -q 'lock_music_writer' "$RUNNER"; then
    fail_msg "likes apply paths must share the music-ingest writer lock"
  fi
  if ! rg -F -q 'pending-imports' "$RUNNER" || ! rg -F -q 'pending-fetch' "$RUNNER"; then
    fail_msg "likes must refuse writes during unresolved import/fetch/promotion"
  fi
  if ! rg -q 'source_secrets' "$RUNNER"; then
    fail_msg "runner must implement source_secrets"
  fi
  if ! rg -F -q 'set -a' "$RUNNER" || ! rg -F -q 'set +a' "$RUNNER"; then
    fail_msg "source_secrets must export via set -a / set +a (launchd never sources zshrc)"
  fi
  if ! rg -F -q '.zsh/secrets.env' "$RUNNER"; then
    fail_msg "source_secrets must source ~/.zsh/secrets.env"
  fi
  if ! rg -F -q '.config/music-likes/secrets.env' "$RUNNER"; then
    fail_msg "source_secrets must source the ~/.config/music-likes/secrets.env overlay"
  fi
  if rg -q '^MUSIC_LIKES_(SPOTIFY_CLIENT_ID|SPOTIFY_CLIENT_SECRET|SPOTIFY_REFRESH_TOKEN|SOULSEEK_USER|SOULSEEK_PASS)=$' "$RUNNER"; then
    fail_msg "generated secrets stub must be comment-only so it cannot erase global credentials"
  fi
  if ! awk '/^cmd_export\(\)/ { inside = 1 } inside { print } inside && /^}/ { exit }' "$RUNNER" | rg -q 'source_secrets'; then
    fail_msg "export and --login must source the documented credential files"
  fi
  if ! rg -F -q 'elif [[ -f "${DEST_MATCH}" ]]' "$RUNNER"; then
    fail_msg "installed LaunchAgent runner must fall back to the installed match helper"
  fi
  if ! rg -q -e '--scheduled' "$RUNNER"; then
    fail_msg "runner must accept --scheduled (the plist creds-skip marker)"
  fi
  if ! rg -F -q 'sync skipped' "$RUNNER"; then
    fail_msg "scheduled runs must log a creds skip and exit 0 (never a 15-minute fail loop)"
  fi
  if ! rg -F -q 'uv run --script' "$RUNNER"; then
    fail_msg "runner must invoke the helper via uv run --script (never its shebang from launchd)"
  fi
  if ! rg -F -q 'caffeinate -i' "$RUNNER"; then
    fail_msg "sockseek passes must wrap caffeinate -i so idle sleep never freezes a backfill"
  fi
  if ! rg -F -q -- '--output-dir "${STATE_DIR}/inbox"' "$RUNNER"; then
    fail_msg "sockseek live output must be the sidecar inbox at STATE_DIR/inbox, not complete/"
  fi
  if rg -F -q -- '--output-dir "$(complete_dir)' "$RUNNER" \
    || rg -F -q -- '--output-dir "${STATE_DIR}/complete' "$RUNNER"; then
    fail_msg "sockseek must never write live into complete/ (ingest prune wipes in-flight files)"
  fi
  if ! rg -F -q -- '--index-path "${STATE_DIR}/index-flac.csv"' "$RUNNER" \
    || ! rg -F -q -- '--index-path "${STATE_DIR}/index-mp3.csv"' "$RUNNER"; then
    fail_msg "sockseek passes need per-format --index-path so a FLAC hit never suppresses the MP3 job"
  fi
  if ! rg -F -q -- '--format flac' "$RUNNER"; then
    fail_msg "fetch must run a --format flac pass"
  fi
  if ! rg -F -q -- '--min-bitrate 320' "$RUNNER"; then
    fail_msg "the MP3 pass must require --min-bitrate 320"
  fi
  if ! rg -F -q -- '--time-format s' "$RUNNER"; then
    fail_msg "sockseek must get --time-format s (missing.csv Length is integer seconds)"
  fi
  if ! rg -q 'promote_finished_audio' "$RUNNER"; then
    fail_msg "runner must promote finished inbox files via promote_finished_audio"
  fi
  if ! rg -F -q 'promote --apply disabled' "$RUNNER"; then
    fail_msg "promotion must be disabled until reviewed per-row identity, hash and decoder proof"
  fi
  if rg -F -q 'promote_finished_audio 0' "$RUNNER"; then
    fail_msg "fetch/sync must never auto-promote rc=0 or stale sidecar audio"
  fi
  if ! rg -F -q 'review-required' "$RUNNER"; then
    fail_msg "rc=0 downloads must still retain a reconciliation marker"
  fi
  if ! rg -F -q -- "! -iname '*.incomplete'" "$RUNNER"; then
    fail_msg "promote must leave *.incomplete files in the inbox for sockseek to resume"
  fi
  if rg -F -q 'downloading/' "$RUNNER" || rg -F -q 'Downloads/downloading' "$RUNNER"; then
    fail_msg "runner must never write into Soulseek Qt's downloading/ tree"
  fi
  if runner_without_manual_sockseek | rg -F -q -- '--skip-music-dir'; then
    fail_msg "--skip-music-dir is manual-only (cmd_sockseek); sync/fetch must never pass it"
  fi
  if runner_without_manual_sockseek | rg -q 'spotify-likes'; then
    fail_msg "spotify-likes is manual-only (cmd_sockseek); the scheduled path must never use it"
  fi
fi

if [[ -f "$MATCH" ]]; then
  if ! head -n 1 "$MATCH" | rg -q 'uv run --script'; then
    fail_msg "helper must use a uv run --script shebang"
  fi
  if ! rg -F -q -- '--self-test' "$MATCH"; then
    fail_msg "helper must ship a --self-test"
  fi
  if ! rg -q 'parse_mix_version' "$MATCH"; then
    fail_msg "helper must parse mix versions via parse_mix_version"
  fi
  if ! rg -q 'mix_class' "$MATCH"; then
    fail_msg "helper must hard-gate matches on mix_class"
  fi
  if ! rg -F -q 'aac-does-not-own-mp3-slot' "$MATCH"; then
    fail_msg "helper self-test must prove AAC does not satisfy the MP3 320 slot"
  fi
  if ! rg -F -q 'isrc-expands-format-rows' "$MATCH"; then
    fail_msg "helper self-test must prove an ISRC seed expands to all compatible format rows"
  fi
  if ! rg -F -q 'backoff-deadline-stable-before-deadline' "$MATCH"; then
    fail_msg "helper self-test must prove polling cannot push a retry deadline forward forever"
  fi
  if ! rg -F -q 'secrets.token_urlsafe' "$MATCH" \
    || ! rg -F -q 'secrets.compare_digest' "$MATCH" \
    || ! rg -F -q '"state": oauth_state' "$MATCH"; then
    fail_msg "Spotify loopback OAuth must generate and verify a state nonce"
  fi
  if ! rg -F -q 'Track URI' "$MATCH"; then
    fail_msg "helper must read the Exportify 'Track URI' header"
  fi
  if ! rg -F -q 'Artist,Title,Album,Length' "$MATCH"; then
    fail_msg "helper must emit sockseek headers Artist,Title,Album,Length"
  fi
  if ! rg -q 'decode_path' "$MATCH"; then
    fail_msg "helper must decode beets relative BLOB paths via decode_path"
  fi
  if ! rg -F -q '#EXTM3U' "$MATCH"; then
    fail_msg "playlist writer must emit an #EXTM3U header"
  fi
  if ! rg -F -q '#EXTINF:' "$MATCH"; then
    fail_msg "playlist writer must emit #EXTINF lines"
  fi
  if ! rg -F -q -- '"../' "$MATCH" && ! rg -F -q -- "'../" "$MATCH"; then
    fail_msg "playlist entries must be ../-relative (Navidrome resolves playlist-relative)"
  fi
fi

for target in "$RUNNER" "$MATCH" "$PLIST"; do
  if [[ ! -f "$target" ]]; then
    continue
  fi
  label="$(basename "$target")"
  if rg -q -e '--no-incomplete-ext|--searches-per-time|--searches-renew-time|--concurrent-searches|--concurrent-jobs' "$target"; then
    fail_msg "$label must not tune Soulseek search-rate/concurrency flags (defaults are the ban guard)"
  fi
  if rg -F -q -- '<key>TimeOut</key>' "$target"; then
    fail_msg "$label must not set a launchd TimeOut key (unimplemented upstream)"
  fi
  if rg -i -q -e 'lidarr|slskd|soularr|spotipy|spotdl|deemix' "$target"; then
    fail_msg "$label must not substitute banned stack components (Spotify Web API + sockseek only)"
  fi
  if rg -q '/Users/' "$target"; then
    fail_msg "$label must not hardcode /Users/ paths"
  fi
  if [[ "$target" != "$RUNNER" ]] && rg -F -q -- '--skip-music-dir' "$target"; then
    fail_msg "$label must never pass --skip-music-dir"
  fi
done

if [[ -f "$PLIST" ]]; then
  if ! rg -q '<key>StartInterval</key>' "$PLIST"; then
    fail_msg "likes plist must StartInterval (poll, not watch)"
  fi
  if ! rg -q '<integer>900</integer>' "$PLIST"; then
    fail_msg "likes plist must tick every 900 seconds"
  fi
  if ! rg -q '<string>sync</string>' "$PLIST"; then
    fail_msg "likes plist must invoke sync"
  fi
  if ! rg -q '<string>--apply</string>' "$PLIST"; then
    fail_msg "likes plist must pass --apply"
  fi
  if ! rg -q '<string>--scheduled</string>' "$PLIST"; then
    fail_msg "likes plist must pass --scheduled so missing creds skip instead of failing"
  fi
  if rg -q 'WatchPaths' "$PLIST"; then
    fail_msg "likes plist must not WatchPaths (polling sync; ingest already watches complete/)"
  fi
  if rg -q 'TimeOut' "$PLIST"; then
    fail_msg "launchd TimeOut is unimplemented upstream; likes plist must not set it"
  fi
  if rg -i -q -e 'password|secret|token|op://' "$PLIST"; then
    fail_msg "likes plist must not carry secret-looking values (secrets live in env files only)"
  fi
  if command -v plutil >/dev/null 2>&1; then
    rendered_plist="$(mktemp "${TMPDIR:-/tmp}/music-likes-plist.XXXXXX")"
    sed "s#{{ \.chezmoi\.homeDir }}#${HOME}#g" "$PLIST" >"$rendered_plist"
    if ! plutil -lint "$rendered_plist" >/dev/null; then
      fail_msg "rendered likes plist must pass plutil -lint"
    fi
    rm -f "$rendered_plist"
  fi
fi

if [[ -f "$PIN" ]]; then
  if ! rg -q '"3\.0\.6"' "$PIN"; then
    fail_msg "sockseek pin must be version 3.0.6"
  fi
  if ! rg -F -q 'b7b9602b3ea0d8724b2a4dd1370c97f2f1f7175f901e7088dad714352c4926d9' "$PIN"; then
    fail_msg "sockseek pin must record the v3.0.6 sha256"
  fi
  if ! rg -F -q 'osx-arm64' "$PIN"; then
    fail_msg "sockseek pin must target the osx-arm64 asset"
  fi
fi

if [[ -f "$MACOS" ]]; then
  if ! rg -F -q 'executable_music-likes' "$MACOS"; then
    fail_msg "macos.sh must install music-likes when the runner source exists"
  fi
  if ! rg -q 'MUSIC_LIKES_REPO' "$MACOS"; then
    fail_msg "macos.sh must export MUSIC_LIKES_REPO when invoking the likes runner"
  fi
fi

if [[ -f "$NAVIDROME" ]]; then
  if ! rg -F -q "PlaylistsPath = 'Playlists'" "$NAVIDROME"; then
    fail_msg "navidrome must scope playlist import via PlaylistsPath = 'Playlists'"
  fi
fi

if [[ -f "$ENV_EXAMPLE" ]]; then
  for name in MUSIC_LIKES_SPOTIFY_CLIENT_ID MUSIC_LIKES_SPOTIFY_CLIENT_SECRET \
    MUSIC_LIKES_SPOTIFY_REFRESH_TOKEN MUSIC_LIKES_SOULSEEK_USER MUSIC_LIKES_SOULSEEK_PASS; do
    if ! rg -q "^${name}=$" "$ENV_EXAMPLE"; then
      fail_msg ".env.example must list ${name} without a value"
    fi
  done
  if ! rg -F -q '.config/music-likes/secrets.env' "$ENV_EXAMPLE"; then
    fail_msg ".env.example must point music-likes users to the credential file launchd sources"
  fi
fi

if [[ -f "$GITIGNORE" ]] && command -v git >/dev/null 2>&1; then
  if ! git -C "$ROOT" check-ignore --no-index -q .config/music-likes/secrets.env \
    || ! git -C "$ROOT" check-ignore --no-index -q nested/private/secrets.env; then
    fail_msg ".gitignore must ignore secrets.env overlays at any depth"
  fi
fi

if [[ -f "$BREW_AGENTS" ]]; then
  if ! rg -F -q 'rig/brew/sockseek-pin.json' "$BREW_AGENTS" \
    || ! rg -q -i 'checksum|sha256' "$BREW_AGENTS" \
    || ! rg -q -i 'not (installed by|a )?Homebrew|not Homebrew' "$BREW_AGENTS"; then
    fail_msg "rig/brew/AGENTS.md must document the checksum-pinned non-Homebrew sockseek pin"
  fi
fi

if [[ -f "$DOCS" ]]; then
  if ! rg -F -q 'just music-likes' "$DOCS"; then
    fail_msg "music.mdx must document just music-likes"
  fi
  if ! rg -q -i -e 'account B|second Soulseek account' "$DOCS"; then
    fail_msg "music.mdx must document the second Soulseek account used for sockseek fetches"
  fi
  if ! rg -q -i 'unlike' "$DOCS"; then
    fail_msg "music.mdx must document unliking behavior"
  fi
  if ! rg -q -i -e 'never delet|not delet|files untouched|removes.{0,30}only' "$DOCS"; then
    fail_msg "music.mdx must document that unlike removes only playlist rows, never library files"
  fi
  if ! rg -q -i -e 'sidecar|music-likes/inbox' "$DOCS"; then
    fail_msg "music.mdx must document the sidecar inbox (never a live complete/ output-dir)"
  fi
  if ! rg -F -q 'Exportify' "$DOCS"; then
    fail_msg "music.mdx must document the Exportify-compatible liked.csv"
  fi
  if ! rg -F -q '## First setup' "$DOCS" \
    || ! rg -F -q 'http://127.0.0.1:48721/callback' "$DOCS" \
    || ! rg -F -q 'just music-likes-install --dry-run' "$DOCS" \
    || ! rg -q -i 'review-required.*marker' "$DOCS"; then
    fail_msg "music.mdx must document credential/login preview and the review-required fetch hold"
  fi
  if rg -q -i 'first successful (scheduled or manual apply|sync --apply).*full backfill' "$DOCS"; then
    fail_msg "music.mdx must not promise unattended full backfill before identity review"
  fi
  if rg -q '/Users/' "$DOCS"; then
    fail_msg "music.mdx must not hardcode /Users/ paths"
  fi
  if rg -q -e 'AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}|BEGIN ((RSA|OPENSSH|EC|DSA|ENCRYPTED) )?PRIVATE KEY' "$DOCS"; then
    fail_msg "music.mdx must not contain token-shaped literals (docs-sensitive parity)"
  fi
fi

if [[ "$fail" -ne 0 ]]; then
  printf 'music-likes: FAIL\n' >&2
  exit 1
fi

printf 'music-likes: ok\n'
