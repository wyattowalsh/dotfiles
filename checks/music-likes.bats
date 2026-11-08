#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# Offline music-likes contract (no live Spotify/Soulseek/launchctl/beets writes).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/music-likes-bats.XXXXXX")"
  DEST_HOME="$SANDBOX/dest_home"
  RUNNER="$REPO_ROOT/rig/home/dot_local/bin/executable_music-likes"
  MATCH_BIN="$REPO_ROOT/rig/home/dot_local/bin/executable_music-likes-match"
  mkdir -p "$DEST_HOME/.local/bin" "$DEST_HOME/Library/LaunchAgents" "$DEST_HOME/Library/Logs/music-likes"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$DEST_HOME/.local/bin/launchctl"
  chmod +x "$DEST_HOME/.local/bin/launchctl"
  printf '#!/usr/bin/env bash\nprintf "music-fixture\\n"\n' >"$DEST_HOME/.local/bin/hostname"
  chmod +x "$DEST_HOME/.local/bin/hostname"
}

teardown() {
  rm -rf "$SANDBOX"
}

@test "include-library forwards the exact matcher flag" {
  likes_env
  run bash -c 'source "$1"; run_helper() { printf "%s\n" "$*"; }; cmd_match --apply --include-library' _ "$RUNNER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"apply match --apply --include-library"* ]]
}

@test "include-library sync does local matching without Spotify or acquisition credentials" {
  likes_env
  run bash -c 'source "$1"; source_secrets() { :; }; flock() { return 0; }; run_helper() { printf "%s\n" "$*"; }; unset MUSIC_LIKES_SPOTIFY_CLIENT_ID MUSIC_LIKES_SPOTIFY_CLIENT_SECRET MUSIC_LIKES_SPOTIFY_REFRESH_TOKEN MUSIC_LIKES_SOULSEEK_USER MUSIC_LIKES_SOULSEEK_PASS; cmd_sync --apply --include-library' _ "$RUNNER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"apply match --apply --include-library"* ]]
  [[ "$output" != *"apply export"* ]]
  [[ "$output" == *"acquisition credentials absent"* ]]
}

@test "library fetch projection retains source queue and holds unresolved editions" {
  require_uv
  local fixture_python fixture_uv
  fixture_python="$(uv run --offline --no-project python -I -c 'import sys; print(sys.executable)')"
  fixture_uv="$(uv run --offline --no-project python -I -c 'import os; print(os.environ["UV"])')"
  likes_env
  export UV_PYTHON="$fixture_python"
  export PATH="$(dirname "$fixture_uv"):$PATH"
  local src="$SANDBOX/missing.csv" flac="$SANDBOX/flac.csv" mp3="$SANDBOX/mp3.csv" before
  "$fixture_uv" run --offline --no-project python -I - "$src" <<'PY'
import csv,json,sys
with open(sys.argv[1], 'w', newline='') as handle:
    writer=csv.DictWriter(handle, fieldnames=['Artist','Title','Album','Length','Format','Origin','IdentityStatus','SourceEvidence'])
    writer.writeheader()
    writer.writerow(dict(Artist='Josh & Wesz',Title='Like Thiz',Album='Goodgreef Xtra Hard',Length='402',Format='flac',Origin='library',IdentityStatus='source-anchored',SourceEvidence=json.dumps({'members':[{'path':'MP3/Like Thiz.mp3','sha256':'0'*64}]})))
    writer.writerow(dict(Artist='',Title='Unidentified',Album='',Length='0',Format='mp3-320',Origin='library',IdentityStatus='unresolved',SourceEvidence='{}'))
PY
  before="$(/usr/bin/shasum -a 256 "$src")"
  run bash -c 'source "$1"; split_missing_csv "$2" "$3" "$4"' _ "$RUNNER" "$src" "$flac" "$mp3"
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing rows: 1 flac, 0 mp3"* ]]
  [[ "$output" == *"held for identity/source review"* ]]
  [ "$(/usr/bin/shasum -a 256 "$src")" = "$before" ]
  [ "$(wc -l <"$flac" | tr -d ' ')" -eq 2 ]
  [ "$(wc -l <"$mp3" | tr -d ' ')" -eq 1 ]
}

legacy_host_identity() {
  printf '#!/usr/bin/env bash\nprintf "Darwin\\n"\n' >"$DEST_HOME/.local/bin/uname"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\n' "$1" >"$DEST_HOME/.local/bin/hostname"
  printf '#!/usr/bin/env bash\ncase "$1" in -un) printf "%%s\\n" %q ;; -u) printf "%%s\\n" %q ;; *) exit 1 ;; esac\n' \
    "$2" "$3" >"$DEST_HOME/.local/bin/id"
  chmod +x "$DEST_HOME/.local/bin/uname" "$DEST_HOME/.local/bin/hostname" "$DEST_HOME/.local/bin/id"
}

# Sandbox env for the runner: dest HOME, repo pointer, and the state-dir override
# the helper honors (plan §9.1) so no run touches the real music-likes state.
likes_env() {
  export HOME="$DEST_HOME"
  export MUSIC_LIKES_REPO="$REPO_ROOT"
  export MUSIC_LIKES_STATE_DIR="$DEST_HOME/.local/share/music-likes"
}

require_uv() {
  command -v uv >/dev/null 2>&1 || skip "uv not on PATH"
}

# Fixtures are generated outside the runner and each untrusted archive gets its
# own empty directory. The archive-writing Python never imports from that dir.
make_sockseek_archive() {
  local kind="$1" dir archive
  dir="$(mktemp -d "$SANDBOX/archive.XXXXXX")"
  archive="$dir/pinned.tar.gz"
  UV_NO_PROJECT=1 uv run --offline --no-project python -I - "$archive" "$kind" <<'PY'
import gzip
import io
import sys
import tarfile

archive, kind = sys.argv[1:]
if kind == "bomb-size":
    # A claimed huge member; do not allocate or write its payload.
    info = tarfile.TarInfo("release/sockseek")
    info.size = 129 * 1024 * 1024
    with gzip.open(archive, "wb") as out:
        out.write(info.tobuf())
    sys.exit(0)

with tarfile.open(archive, "w:gz") as tar:
    def add(name, data=b"", member_type=tarfile.REGTYPE, link=""):
        info = tarfile.TarInfo(name)
        info.type = member_type
        info.linkname = link
        info.size = len(data) if member_type == tarfile.REGTYPE else 0
        tar.addfile(info, io.BytesIO(data) if info.size else None)

    add("release/sockseek", b"synthetic pinned binary\n")
    add("release/notes.txt", b"decoy must never be extracted\n")
    if kind == "traversal":
        add("../escaped/sockseek", b"escape")
    elif kind == "absolute":
        add("/escaped/sockseek", b"escape")
    elif kind == "symlink":
        add("release/link", member_type=tarfile.SYMTYPE, link="../../escaped")
    elif kind == "hardlink":
        add("release/link", member_type=tarfile.LNKTYPE, link="release/sockseek")
    elif kind == "device":
        add("release/device", member_type=tarfile.CHRTYPE)
    elif kind == "duplicate":
        add("release/sockseek", b"second copy")
    elif kind == "second-binary":
        add("other/sockseek", b"another candidate")
    elif kind != "safe":
        raise ValueError(f"unknown fixture: {kind}")
PY
  printf '%s\n' "$archive"
}

assert_sockseek_archive_rejected() {
  local kind="$1" archive extract
  archive="$(make_sockseek_archive "$kind")" || return 1
  [ -s "$archive" ]
  extract="$(mktemp -d "$SANDBOX/extract.XXXXXX")"
  run bash -c 'source "$1"; extract_sockseek_pin "$2" "$3"' _ "$RUNNER" "$archive" "$extract"
  [ "$status" -ne 0 ]
  case "$kind" in
    traversal | absolute) [[ "$output" == *"unsafe archive member path"* ]] ;;
    symlink | hardlink | device) [[ "$output" == *"non-regular archive member"* ]] ;;
    duplicate) [[ "$output" == *"duplicate archive member"* ]] ;;
    second-binary) [[ "$output" == *"multiple sockseek members"* ]] ;;
    bomb-size) [[ "$output" == *"archive member exceeds size limit"* ]] ;;
  esac
  [ ! -e "$extract/sockseek" ]
  [ -z "$(find "$extract" -mindepth 1 -print -quit)" ]
  [ ! -e "$SANDBOX/escaped/sockseek" ]
}

@test "music-likes static contract passes" {
  run "$REPO_ROOT/checks/music-likes.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"music-likes: ok"* ]]
}

@test "music-likes doctor does not mutate dest home" {
  likes_env
  before="$(find "$DEST_HOME" -type f | LC_ALL=C sort | cksum)"
  run "$RUNNER" doctor
  [ "$status" -eq 0 ]
  after="$(find "$DEST_HOME" -type f | LC_ALL=C sort | cksum)"
  [ "$before" = "$after" ]
}

@test "sync/fetch/install --dry-run write nothing to dest home" {
  likes_env
  run "$RUNNER" sync --dry-run
  [ "$status" -eq 0 ]
  run "$RUNNER" fetch --dry-run
  [ "$status" -eq 0 ]
  run "$RUNNER" install --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run: would bootstrap"* ]]
  [ ! -f "$MUSIC_LIKES_STATE_DIR/liked.csv" ]
  [ ! -f "$MUSIC_LIKES_STATE_DIR/missing.csv" ]
  [ ! -f "$DEST_HOME/Music/Library/Playlists/Liked Songs.m3u" ]
  [ ! -f "$DEST_HOME/.local/bin/music-likes" ]
  [ ! -f "$DEST_HOME/.local/bin/music-likes-match" ]
  [ ! -f "$DEST_HOME/.local/bin/sockseek" ]
  [ ! -f "$DEST_HOME/Library/LaunchAgents/com.wyattowalsh.music-likes.plist" ]
  [ ! -f "$DEST_HOME/.config/sockseek/sockseek.conf" ]
  [ ! -f "$DEST_HOME/.config/music-likes/secrets.env" ]
}

@test "legacy likes install refuses both migrated native identities before writes" {
  likes_env
  for profile in 'w4w-mbp ww 502' 'MacBookAir wyattwalsh 501'; do
    read -r host_name user_name user_id <<<"$profile"
    legacy_host_identity "$host_name" "$user_name" "$user_id"
    before="$(find "$DEST_HOME" -type f | LC_ALL=C sort | cksum)"
    run "$RUNNER" install
    [ "$status" -ne 0 ]
    [[ "$output" == *"legacy music service install retired"* ]]
    [[ "$output" == *"retained manual rollback plists"* ]]
    after="$(find "$DEST_HOME" -type f | LC_ALL=C sort | cksum)"
    [ "$before" = "$after" ]
    [ ! -d "$MUSIC_LIKES_STATE_DIR" ]
    [ ! -f "$DEST_HOME/.local/bin/sockseek" ]
  done
}

@test "retired likes preview is inert and wrong native uid remains outside the pair" {
  likes_env
  legacy_host_identity w4w-mbp ww 502
  run "$RUNNER" install --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"no copy, render or activation"* ]]
  [ ! -d "$MUSIC_LIKES_STATE_DIR" ]
  legacy_host_identity w4w-mbp ww 999
  run "$RUNNER" install --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run: would bootstrap"* ]]
}

@test "sockseek pin safe archive extracts only its single regular binary" {
  require_uv
  likes_env
  local archive extract
  archive="$(make_sockseek_archive safe)"
  extract="$(mktemp -d "$SANDBOX/extract.XXXXXX")"
  run bash -c 'source "$1"; extract_sockseek_pin "$2" "$3"' _ "$RUNNER" "$archive" "$extract"
  [ "$status" -eq 0 ]
  [ "$(<"$extract/sockseek")" = "synthetic pinned binary" ]
  [ "$(find "$extract" -type f | wc -l | tr -d ' ')" -eq 1 ]
  [ ! -e "$extract/release/notes.txt" ]
  [ ! -e "$DEST_HOME/.local/bin/sockseek" ]
}

@test "sockseek pin rejects traversal archive" {
  require_uv
  likes_env
  assert_sockseek_archive_rejected traversal
}

@test "sockseek pin rejects absolute archive paths" {
  require_uv
  likes_env
  assert_sockseek_archive_rejected absolute
}

@test "sockseek pin rejects symlink archive" {
  require_uv
  likes_env
  assert_sockseek_archive_rejected symlink
}

@test "sockseek pin rejects hardlink archive" {
  require_uv
  likes_env
  assert_sockseek_archive_rejected hardlink
}

@test "sockseek pin rejects device archive" {
  require_uv
  likes_env
  assert_sockseek_archive_rejected device
}

@test "sockseek pin rejects duplicate archive members" {
  require_uv
  likes_env
  assert_sockseek_archive_rejected duplicate
}

@test "sockseek pin rejects multiple regular sockseek candidates" {
  require_uv
  likes_env
  assert_sockseek_archive_rejected second-binary
}

@test "sockseek pin rejects claimed decompression bomb size" {
  require_uv
  likes_env
  assert_sockseek_archive_rejected bomb-size
}

@test "sockseek pin and CSV parsing fail closed without uv" {
  likes_env
  local extract src flac mp3
  extract="$(mktemp -d "$SANDBOX/extract.XXXXXX")"
  run bash -c 'source "$1"; PATH=/nonexistent; extract_sockseek_pin "$2" "$3"' \
    _ "$RUNNER" "$SANDBOX/absent.tar.gz" "$extract"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing command: uv"* ]]
  [ -z "$(find "$extract" -mindepth 1 -print -quit)" ]
  src="$SANDBOX/missing.csv"
  flac="$SANDBOX/flac.csv"
  mp3="$SANDBOX/mp3.csv"
  printf '%s\n' 'Artist,Title,Album,Length,Format' 'Fixture,Song,Album,180,flac' >"$src"
  run bash -c 'source "$1"; PATH=/nonexistent; split_missing_csv "$2" "$3" "$4"' \
    _ "$RUNNER" "$src" "$flac" "$mp3"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing command: uv"* ]]
  [ ! -e "$flac" ]
  [ ! -e "$mp3" ]
}

@test "installed scheduled sync uses dest helper and comment overlay preserves global secrets" {
  if ! command -v uv >/dev/null 2>&1; then
    skip "uv not on PATH"
  fi
  likes_env
  cp "$RUNNER" "$DEST_HOME/.local/bin/music-likes"
  cat >"$DEST_HOME/.local/bin/music-likes-match" <<'PY'
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = []
# ///
import os
import sys
from pathlib import Path

names = (
    "MUSIC_LIKES_SPOTIFY_CLIENT_ID",
    "MUSIC_LIKES_SPOTIFY_CLIENT_SECRET",
    "MUSIC_LIKES_SPOTIFY_REFRESH_TOKEN",
    "MUSIC_LIKES_SOULSEEK_USER",
    "MUSIC_LIKES_SOULSEEK_PASS",
)
assert all(os.environ.get(name) for name in names)
with (Path.home() / "helper-calls").open("a", encoding="utf-8") as handle:
    handle.write(f"{Path(__file__)} {' '.join(sys.argv[1:])}\n")
PY
  chmod +x "$DEST_HOME/.local/bin/music-likes" "$DEST_HOME/.local/bin/music-likes-match"
  mkdir -p "$DEST_HOME/.zsh" "$DEST_HOME/.config/music-likes"
  printf '%s\n' \
    'MUSIC_LIKES_SPOTIFY_CLIENT_ID=x' \
    'MUSIC_LIKES_SPOTIFY_CLIENT_SECRET=x' \
    'MUSIC_LIKES_SPOTIFY_REFRESH_TOKEN=x' \
    'MUSIC_LIKES_SOULSEEK_USER=x' \
    'MUSIC_LIKES_SOULSEEK_PASS=x' \
    >"$DEST_HOME/.zsh/secrets.env"
  printf '%s\n' \
    '# Comment-only overlay must not erase the global values.' \
    '# MUSIC_LIKES_SPOTIFY_CLIENT_ID=' \
    '# MUSIC_LIKES_SPOTIFY_CLIENT_SECRET=' \
    '# MUSIC_LIKES_SPOTIFY_REFRESH_TOKEN=' \
    '# MUSIC_LIKES_SOULSEEK_USER=' \
    '# MUSIC_LIKES_SOULSEEK_PASS=' \
    >"$DEST_HOME/.config/music-likes/secrets.env"
  unset MUSIC_LIKES_REPO
  run "$DEST_HOME/.local/bin/music-likes" sync --apply --scheduled
  [ "$status" -eq 0 ]
  [[ "$output" != *"secrets missing"* ]]
  [ "$(wc -l <"$DEST_HOME/helper-calls")" -eq 3 ]
  grep -q ' export --apply$' "$DEST_HOME/helper-calls"
  grep -q ' match --apply$' "$DEST_HOME/helper-calls"
  grep -q ' playlist --apply$' "$DEST_HOME/helper-calls"
}

@test "export --login sources documented credential files" {
  if ! command -v uv >/dev/null 2>&1; then
    skip "uv not on PATH"
  fi
  likes_env
  mkdir -p "$DEST_HOME/.zsh"
  printf '%s\n' \
    'MUSIC_LIKES_SPOTIFY_CLIENT_ID=x' \
    'MUSIC_LIKES_SPOTIFY_CLIENT_SECRET=x' \
    >"$DEST_HOME/.zsh/secrets.env"
  cat >"$DEST_HOME/.local/bin/music-likes-match" <<'PY'
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = []
# ///
import os
import sys
from pathlib import Path

assert os.environ.get("MUSIC_LIKES_SPOTIFY_CLIENT_ID")
assert os.environ.get("MUSIC_LIKES_SPOTIFY_CLIENT_SECRET")
(Path.home() / "login-call").write_text(" ".join(sys.argv[1:]), encoding="utf-8")
PY
  chmod +x "$DEST_HOME/.local/bin/music-likes-match"
  unset MUSIC_LIKES_REPO
  run "$RUNNER" export --login
  [ "$status" -eq 0 ]
  grep -q 'export --login' "$DEST_HOME/login-call"
}

@test "promotion refuses corrupt/unrelated suffix candidates even when explicitly requested" {
  likes_env
  local inbox="$MUSIC_LIKES_STATE_DIR/inbox"
  mkdir -p "$inbox/.sockseek-staging"
  printf 'not audio' >"$inbox/unrelated.flac"
  printf 'x' >"$inbox/partial.flac.incomplete"
  run "$RUNNER" promote --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"promote --apply disabled"* ]]
  [ -f "$inbox/unrelated.flac" ]
  [ -f "$inbox/partial.flac.incomplete" ]
  [ ! -d "$DEST_HOME/Soulseek Downloads/complete/music-likes" ]
  run "$RUNNER" promote --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"unverified sidecar candidate"* ]]
  [[ "$output" != *"partial.flac.incomplete"* ]]
}

@test "music-likes-match self-test passes against fixtures" {
  if ! command -v uv >/dev/null 2>&1; then
    skip "uv not on PATH"
  fi
  export MUSIC_LIKES_STATE_DIR="$DEST_HOME/.local/share/music-likes"
  run env MUSIC_LIKES_FIXTURE_DIR="$REPO_ROOT/checks/fixtures/music-likes" \
    uv run --script "$MATCH_BIN" --self-test
  [ "$status" -eq 0 ]
}

@test "unlike drops only the playlist row, never library files" {
  if ! command -v uv >/dev/null 2>&1; then
    skip "uv not on PATH"
  fi
  if ! command -v sqlite3 >/dev/null 2>&1; then
    skip "sqlite3 not on PATH"
  fi
  likes_env
  mkdir -p "$MUSIC_LIKES_STATE_DIR" "$DEST_HOME/.local/share/beets" "$DEST_HOME/Music/Library/Playlists"
  sqlite3 "$DEST_HOME/.local/share/beets/library.db" <"$REPO_ROOT/checks/fixtures/music-likes/library.sql"
  grep -v 'spotify:track:both' "$REPO_ROOT/checks/fixtures/music-likes/liked.csv" >"$MUSIC_LIKES_STATE_DIR/liked.csv"
  mkdir -p "$DEST_HOME/Music/Library/FLAC/Both Artist/Both Album" "$DEST_HOME/Music/Library/MP3/Both Artist/Both Album" "$DEST_HOME/Music/Library/MP3/Showtek/2010 - Analogue Players In A Digital World"
  printf 'x' >"$DEST_HOME/Music/Library/FLAC/Both Artist/Both Album/01 Already Both.flac"
  printf 'x' >"$DEST_HOME/Music/Library/MP3/Both Artist/Both Album/01 Already Both.mp3"
  printf 'x' >"$DEST_HOME/Music/Library/MP3/Showtek/2010 - Analogue Players In A Digital World/01 Hear This.mp3"
  run uv run --script "$MATCH_BIN" match --apply
  [ "$status" -eq 0 ]
  run uv run --script "$MATCH_BIN" playlist --apply
  [ "$status" -eq 0 ]
  local m3u="$DEST_HOME/Music/Library/Playlists/Liked Songs.m3u"
  [ -f "$m3u" ]
  run grep -q 'Already Both' "$m3u"
  [ "$status" -ne 0 ]
  grep -q 'Hear This' "$m3u"
  [ -f "$DEST_HOME/Music/Library/FLAC/Both Artist/Both Album/01 Already Both.flac" ]
  [ -f "$DEST_HOME/Music/Library/MP3/Both Artist/Both Album/01 Already Both.mp3" ]
}

@test "likes plist uses StartInterval 900 with sync --apply --scheduled" {
  local plist="$REPO_ROOT/rig/home/Library/LaunchAgents/com.wyattowalsh.music-likes.plist.tmpl"
  run rg -q 'StartInterval' "$plist"
  [ "$status" -eq 0 ]
  run rg -q '900' "$plist"
  [ "$status" -eq 0 ]
  run rg -q '<string>sync</string>' "$plist"
  [ "$status" -eq 0 ]
  run rg -q '<string>--apply</string>' "$plist"
  [ "$status" -eq 0 ]
  run rg -q '<string>--scheduled</string>' "$plist"
  [ "$status" -eq 0 ]
  run rg -q 'WatchPaths' "$plist"
  [ "$status" -ne 0 ]
  run rg -q 'TimeOut' "$plist"
  [ "$status" -ne 0 ]
  if command -v plutil >/dev/null 2>&1; then
    local rendered="$SANDBOX/music-likes.plist"
    sed "s#{{ \.chezmoi\.homeDir }}#$DEST_HOME#g" "$plist" >"$rendered"
    run plutil -lint "$rendered"
    [ "$status" -eq 0 ]
  fi
}

@test "fetch --dry-run prints both format passes into the sidecar inbox" {
  likes_env
  mkdir -p "$MUSIC_LIKES_STATE_DIR"
  printf '%s\n' \
    'Artist,Title,Album,Length,ISRC,SpotifyId,Format' \
    'Showtek,Hear This,Analogue Players In A Digital World,222,ITC941001118,isrcHit,flac' \
    'Missing Artist,Not In Library (Extended Mix),Missing Album,240,,gone,mp3-320' \
    >"$MUSIC_LIKES_STATE_DIR/missing.csv"
  run "$RUNNER" fetch --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"--format flac"* ]]
  [[ "$output" == *"--min-bitrate 320"* ]]
  [[ "$output" == *"--output-dir ${MUSIC_LIKES_STATE_DIR}/inbox"* ]]
  [[ "$output" == *"index-flac.csv"* ]]
  [[ "$output" == *"index-mp3.csv"* ]]
  [[ "$output" != *"--output-dir "*"/Soulseek Downloads"* ]]
}

@test "header-only queue never promotes an old sidecar candidate" {
  likes_env
  mkdir -p "$MUSIC_LIKES_STATE_DIR/inbox"
  printf '%s\n' 'Artist,Title,Album,Length,ISRC,SpotifyId,Format' >"$MUSIC_LIKES_STATE_DIR/missing.csv"
  printf 'stale or corrupt bytes\n' >"$MUSIC_LIKES_STATE_DIR/inbox/stale.flac"
  run "$RUNNER" fetch --apply
  [ "$status" -eq 0 ]
  [ -f "$MUSIC_LIKES_STATE_DIR/inbox/stale.flac" ]
  [ ! -d "$DEST_HOME/Soulseek Downloads/complete/music-likes" ]
}

@test "rc-zero but partial sockseek output stays unverified, never promoted" {
  likes_env
  mkdir -p "$MUSIC_LIKES_STATE_DIR" "$DEST_HOME/.local/bin"
  printf '%s\n' 'Artist,Title,Album,Length,ISRC,SpotifyId,Format' \
    'Fixture,First,Album,180,,first,flac' \
    'Fixture,Second,Album,180,,second,mp3-320' >"$MUSIC_LIKES_STATE_DIR/missing.csv"
  cat >"$DEST_HOME/.local/bin/sockseek" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$MUSIC_LIKES_STATE_DIR/inbox"
printf 'only one unrelated or corrupt result\n' >"$MUSIC_LIKES_STATE_DIR/inbox/partial.flac"
exit 0
STUB
  chmod +x "$DEST_HOME/.local/bin/sockseek"
  run "$RUNNER" fetch --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"per-row results are unverified"* ]]
  [ -f "$MUSIC_LIKES_STATE_DIR/inbox/partial.flac" ]
  [ ! -d "$DEST_HOME/Soulseek Downloads/complete/music-likes" ]
  [ -n "$(find "$MUSIC_LIKES_STATE_DIR/pending-fetch" -type f -print -quit)" ]
  run "$RUNNER" fetch --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"unresolved fetch marker"* ]]
}

@test "failed synthetic fetch keeps sidecar audio and blocks later promotion" {
  likes_env
  mkdir -p "$MUSIC_LIKES_STATE_DIR" "$DEST_HOME/.local/bin"
  printf '%s\n' 'Artist,Title,Album,Length,ISRC,SpotifyId,Format' \
    'Fixture,Song,Album,180,,fixture,flac' >"$MUSIC_LIKES_STATE_DIR/missing.csv"
  cat >"$DEST_HOME/.local/bin/sockseek" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$MUSIC_LIKES_STATE_DIR/inbox"
printf 'synthetic audio\n' >"$MUSIC_LIKES_STATE_DIR/inbox/fixture.flac"
exit 9
STUB
  chmod +x "$DEST_HOME/.local/bin/sockseek"
  run "$RUNNER" fetch --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"no promotion"* ]]
  [ -f "$MUSIC_LIKES_STATE_DIR/inbox/fixture.flac" ]
  [ ! -d "$DEST_HOME/Soulseek Downloads/complete/music-likes" ]
  [ -n "$(find "$MUSIC_LIKES_STATE_DIR/pending-fetch" -type f -print -quit)" ]
  run "$RUNNER" promote --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"unresolved fetch marker"* ]]
  [ -f "$MUSIC_LIKES_STATE_DIR/inbox/fixture.flac" ]
}

@test "likes writer blocks on unresolved ingest and never calls helper" {
  likes_env
  mkdir -p "$DEST_HOME/.local/share/music-ingest/pending-imports"
  printf 'status=started\n' >"$DEST_HOME/.local/share/music-ingest/pending-imports/unit.fixture"
  run "$RUNNER" playlist --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"unresolved import marker"* ]]
  [ ! -f "$DEST_HOME/Music/Library/Playlists/Liked Songs.m3u" ]
  run "$RUNNER" sync --apply --scheduled
  [ "$status" -ne 0 ]
  [[ "$output" == *"unresolved import marker"* ]]
}

@test "likes scheduled apply skips when ingest owns shared music writer lock" {
  likes_env
  local lock="$DEST_HOME/.local/share/music-ingest/music-writer.lock"
  mkdir -p "$(dirname "$lock")"
  flock "$lock" -c 'sleep 4' &
  local locker=$!
  sleep 0.2
  run "$RUNNER" sync --apply --scheduled
  [ "$status" -eq 0 ]
  [[ "$output" == *"already running"* ]]
  [[ "$output" == *"skipped"* ]]
  [ ! -f "$DEST_HOME/.local/share/music-likes/liked.csv" ]
  wait "$locker"
}

@test "scheduled sync without creds skips cleanly; bare apply fails closed" {
  likes_env
  unset MUSIC_LIKES_SPOTIFY_CLIENT_ID MUSIC_LIKES_SPOTIFY_CLIENT_SECRET \
    MUSIC_LIKES_SPOTIFY_REFRESH_TOKEN MUSIC_LIKES_SOULSEEK_USER MUSIC_LIKES_SOULSEEK_PASS
  run "$RUNNER" sync --apply --scheduled
  [ "$status" -eq 0 ]
  [[ "$output" == *"secrets missing"* ]]
  [[ "$output" == *"skipped"* ]]
  run "$RUNNER" sync --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"secrets missing"* ]]
}
