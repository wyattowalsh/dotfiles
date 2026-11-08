#!/usr/bin/env bats
# Offline music ingest contract (no live launchctl/beets/library writes).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/music-ingest-bats.XXXXXX")"
  DEST_HOME="$SANDBOX/dest_home"
  mkdir -p "$DEST_HOME/.local/bin" "$DEST_HOME/Library/LaunchAgents" "$DEST_HOME/Library/Logs/music-ingest"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$DEST_HOME/.local/bin/launchctl"
  chmod +x "$DEST_HOME/.local/bin/launchctl"
  printf '#!/usr/bin/env bash\nprintf "music-fixture\\n"\n' >"$DEST_HOME/.local/bin/hostname"
  chmod +x "$DEST_HOME/.local/bin/hostname"
}

teardown() {
  rm -rf "$SANDBOX"
}

legacy_host_identity() {
  printf '#!/usr/bin/env bash\nprintf "Darwin\\n"\n' >"$DEST_HOME/.local/bin/uname"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\n' "$1" >"$DEST_HOME/.local/bin/hostname"
  printf '#!/usr/bin/env bash\ncase "$1" in -un) printf "%%s\\n" %q ;; -u) printf "%%s\\n" %q ;; *) exit 1 ;; esac\n' \
    "$2" "$3" >"$DEST_HOME/.local/bin/id"
  chmod +x "$DEST_HOME/.local/bin/uname" "$DEST_HOME/.local/bin/hostname" "$DEST_HOME/.local/bin/id"
}

# No real beet, media decoder or Library is used in the apply-path fixtures.
ingest_fixture() {
  export HOME="$DEST_HOME" MUSIC_INGEST_REPO="$REPO_ROOT" MUSIC_INGEST_SETTLE_SEC=0
  export MUSIC_INGEST_BEET_BIN="$SANDBOX/beet" MUSIC_INGEST_FFPROBE_BIN="$SANDBOX/ffprobe"
  export STUB_IDS="$SANDBOX/ids" STUB_CALLS="$SANDBOX/calls" STUB_MODE="${1:-success}"
  : >"$STUB_IDS"
  : >"$STUB_CALLS"
  mkdir -p "$DEST_HOME/Soulseek Downloads/complete/uploader/Album" "$DEST_HOME/Music/Library/MP3"
  printf 'synthetic audio\n' >"$DEST_HOME/Soulseek Downloads/complete/uploader/Album/track.mp3"
  if [[ "$STUB_MODE" == multi ]]; then
    printf 'synthetic second audio\n' >"$DEST_HOME/Soulseek Downloads/complete/uploader/Album/second.mp3"
  fi
  printf '#!/usr/bin/env bash\nexit 0\n' >"$MUSIC_INGEST_FFPROBE_BIN"
  cat >"$MUSIC_INGEST_BEET_BIN" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$STUB_CALLS"
case "$1" in
  ls)
    if [[ "$STUB_MODE" == baseline-error || ( "$STUB_MODE" == baseline-path-error && "$3" == '$path' && -z "${4:-}" ) ]]; then exit 8; fi
    if [[ "$3" == '$id' ]]; then
      cat "$STUB_IDS"
    elif [[ "$3" == '$path' ]]; then
      if [[ "${4:-}" == id:101 ]]; then
        printf '%s\n' "$HOME/Music/Library/MP3/verified.mp3"
      elif [[ "${4:-}" == id:102 ]]; then
        printf '%s\n' "$HOME/Music/Library/MP3/verified2.mp3"
      elif [[ -z "${4:-}" ]] && grep -qx 101 "$STUB_IDS"; then
        printf '%s\n' "$HOME/Music/Library/MP3/verified.mp3"
      elif [[ -z "${4:-}" ]] && grep -qx 100 "$STUB_IDS"; then
        printf '%s\n' "$HOME/Music/Library/MP3/existing.mp3"
      fi
    else
      exit 3
    fi
    ;;
  import)
    if [[ "$STUB_MODE" == interrupt ]]; then
      kill -TERM "$PPID"
      exit 143
    fi
    if [[ "$STUB_MODE" == multi ]]; then
      cp "$HOME/Soulseek Downloads/complete/uploader/Album/track.mp3" "$HOME/Music/Library/MP3/verified.mp3"
      cp "$HOME/Soulseek Downloads/complete/uploader/Album/second.mp3" "$HOME/Music/Library/MP3/verified2.mp3"
      printf '101\n102\n' >>"$STUB_IDS"
      exit 0
    fi
    next_id=101
    dest="$HOME/Music/Library/MP3/verified.mp3"
    if grep -qx 101 "$STUB_IDS"; then
      next_id=102
      dest="$HOME/Music/Library/MP3/verified2.mp3"
    fi
    if [[ "$STUB_MODE" != fail ]]; then
      cp "$HOME/Soulseek Downloads/complete/uploader/Album/track.mp3" "$dest"
    fi
    if [[ "$STUB_MODE" == wrong-copy ]]; then
      printf 'unrelated bytes\n' >"$dest"
    fi
    if [[ "$STUB_MODE" == success || "$STUB_MODE" == partial || "$STUB_MODE" == wrong-copy ]]; then
      printf '%s\n' "$next_id" >>"$STUB_IDS"
    fi
    if [[ "$STUB_MODE" == partial || "$STUB_MODE" == fail ]]; then exit 2; fi
    ;;
  *) exit 4 ;;
esac
STUB
  chmod +x "$MUSIC_INGEST_BEET_BIN" "$MUSIC_INGEST_FFPROBE_BIN"
}

@test "music-ingest static contract passes" {
  run "$REPO_ROOT/checks/music-ingest.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"music-ingest: ok"* ]]
}

@test "music-ingest doctor does not mutate dest home" {
  export HOME="$DEST_HOME"
  export MUSIC_INGEST_REPO="$REPO_ROOT"
  before="$(find "$DEST_HOME" -type f | LC_ALL=C sort | cksum)"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" doctor
  [ "$status" -eq 0 ]
  after="$(find "$DEST_HOME" -type f | LC_ALL=C sort | cksum)"
  [ "$before" = "$after" ]
}

@test "music-ingest ingest --dry-run does not copy inbox files" {
  export HOME="$DEST_HOME"
  export MUSIC_INGEST_REPO="$REPO_ROOT"
  export MUSIC_INGEST_SETTLE_SEC=0
  mkdir -p "$DEST_HOME/Soulseek Downloads/complete/uploader/Album"
  printf 'not-audio' >"$DEST_HOME/Soulseek Downloads/complete/uploader/Album/skip.txt"
  printf 'x' >"$DEST_HOME/Soulseek Downloads/complete/uploader/Album/track.mp3"
  printf 'x' >"$DEST_HOME/Soulseek Downloads/complete/uploader/loose.mp3"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  [[ "$output" == *"--copy"* ]]
  [[ "$output" == *"proposal only"* ]]
  [[ "$output" == *"uploader/Album"* ]]
  [[ "$output" == *"singletons"* ]]
  [ -f "$DEST_HOME/Soulseek Downloads/complete/uploader/Album/track.mp3" ]
  [ ! -d "$DEST_HOME/Music/Library" ]
}

@test "copy-drain Python ignores planted cwd and PYTHONPATH modules" {
  if ! command -v uv >/dev/null 2>&1; then
    skip "uv not on PATH"
  fi
  export HOME="$DEST_HOME" MUSIC_INGEST_PLANT_MARKER="$SANDBOX/poisoned"
  local untrusted="$SANDBOX/untrusted"
  local complete="$DEST_HOME/Soulseek Downloads/complete/Album"
  local library="$DEST_HOME/Music/Library/Artist"
  mkdir -p "$untrusted" "$complete" "$library"
  printf 'synthetic audio\n' >"$complete/track.mp3"
  cp "$complete/track.mp3" "$library/copy.mp3"
  printf '%s\n' 'import os' 'open(os.environ["MUSIC_INGEST_PLANT_MARKER"], "a").write("hashlib\\n")' >"$untrusted/hashlib.py"
  printf '%s\n' 'import os' 'open(os.environ["MUSIC_INGEST_PLANT_MARKER"], "a").write("json\\n")' >"$untrusted/json.py"
  export PYTHONPATH="$untrusted"
  cd "$untrusted"
  # Load definitions without the final CLI dispatch; never invoke real ingest.
  source <(/usr/bin/sed '$d' "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest")
  run drain_matching_library_copies 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"retain inbox original"* ]]
  [[ "$output" == *"1 0" ]]
  [ ! -e "$MUSIC_INGEST_PLANT_MARKER" ]
  [ -f "$complete/track.mp3" ]
}

@test "music-ingest install --dry-run does not bootstrap launchd" {
  export HOME="$DEST_HOME"
  export MUSIC_INGEST_REPO="$REPO_ROOT"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" install --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run: would bootstrap"* ]]
  [ ! -f "$DEST_HOME/Library/LaunchAgents/com.wyattowalsh.music-ingest.plist" ]
  [ ! -f "$DEST_HOME/.local/bin/music-ingest" ]
}

@test "legacy ingest install refuses both migrated native identities before writes" {
  export HOME="$DEST_HOME" MUSIC_INGEST_REPO="$REPO_ROOT"
  for profile in 'w4w-mbp ww 502' 'MacBookAir wyattwalsh 501'; do
    read -r host_name user_name user_id <<<"$profile"
    legacy_host_identity "$host_name" "$user_name" "$user_id"
    before="$(find "$DEST_HOME" -type f | LC_ALL=C sort | cksum)"
    run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" install
    [ "$status" -ne 0 ]
    [[ "$output" == *"legacy music service install retired"* ]]
    [[ "$output" == *"retained manual rollback plists"* ]]
    after="$(find "$DEST_HOME" -type f | LC_ALL=C sort | cksum)"
    [ "$before" = "$after" ]
    [ ! -d "$DEST_HOME/Music" ]
    [ ! -f "$DEST_HOME/.local/bin/music-ingest" ]
  done
}

@test "retired ingest preview is inert and wrong native uid remains outside the pair" {
  export HOME="$DEST_HOME" MUSIC_INGEST_REPO="$REPO_ROOT"
  legacy_host_identity MacBookAir wyattwalsh 501
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" install --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"no copy, render or activation"* ]]
  [ ! -d "$DEST_HOME/Music" ]
  legacy_host_identity MacBookAir wyattwalsh 999
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" install --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run: would bootstrap"* ]]
}

@test "Brew Bundle retains Pueue binary without restarting its scheduler" {
  run rg -qxF 'brew "pueue", restart_service: false' "$REPO_ROOT/rig/brew/Brewfile"
  [ "$status" -eq 0 ]
  run rg -q 'brew "pueue", restart_service: true' "$REPO_ROOT/rig/brew/Brewfile"
  [ "$status" -eq 1 ]
}

@test "beets config refuses from_scratch and keeps dual copies" {
  run rg -q 'from_scratch: no' "$REPO_ROOT/rig/home/private_dot_config/beets/config.yaml.tmpl"
  [ "$status" -eq 0 ]
  run rg -q 'duplicate_action: keep' "$REPO_ROOT/rig/home/private_dot_config/beets/config.yaml.tmpl"
  [ "$status" -eq 0 ]
}

@test "refine --force-analyze is refused" {
  export HOME="$DEST_HOME"
  export MUSIC_INGEST_REPO="$REPO_ROOT"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" refine --force-analyze
  [ "$status" -ne 0 ]
  [[ "$output" == *"force-analyze"* ]]
}

@test "refine --dry-run does not create library files" {
  export HOME="$DEST_HOME"
  export MUSIC_INGEST_REPO="$REPO_ROOT"
  mkdir -p "$DEST_HOME/Soulseek Downloads/complete/album"
  printf 'x' >"$DEST_HOME/Soulseek Downloads/complete/album/track.mp3"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" refine --dry-run "$DEST_HOME/Soulseek Downloads/complete"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  [ ! -d "$DEST_HOME/Music/Library" ]
}

@test "music-dj-tag self-test (fill-if-missing cannot worsen)" {
  if ! command -v uv >/dev/null 2>&1; then
    skip "uv not on PATH"
  fi
  run uv run --script "$REPO_ROOT/rig/home/dot_local/bin/executable_music-dj-tag" --self-test
  [ "$status" -eq 0 ]
  [[ "$output" == *"self-test ok"* ]]
}

@test "catalog --dry-run does not import while describing MusicBrainz path" {
  export HOME="$DEST_HOME"
  export MUSIC_INGEST_REPO="$REPO_ROOT"
  mkdir -p "$DEST_HOME/Music/Library/Incoming/gdrive-restore/Artist/Album"
  printf 'x' >"$DEST_HOME/Music/Library/Incoming/gdrive-restore/Artist/Album/track.mp3"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" catalog --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  [[ "$output" == *"beet import"* ]]
  [[ "$output" == *"--move"* ]]
  [ -f "$DEST_HOME/Music/Library/Incoming/gdrive-restore/Artist/Album/track.mp3" ]
}

@test "catalog refuses Soulseek complete inbox" {
  export HOME="$DEST_HOME"
  export MUSIC_INGEST_REPO="$REPO_ROOT"
  mkdir -p "$DEST_HOME/Soulseek Downloads/complete/album"
  printf 'x' >"$DEST_HOME/Soulseek Downloads/complete/album/track.mp3"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" catalog --dry-run "$DEST_HOME/Soulseek Downloads/complete"
  [ "$status" -ne 0 ]
  [[ "$output" == *"complete"* ]]
}

@test "enrich --dry-run does not require beet" {
  export HOME="$DEST_HOME"
  export MUSIC_INGEST_REPO="$REPO_ROOT"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" enrich --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  [[ "$output" == *"fetchart"* ]]
}

@test "prepare is an alias for refine (refuses --force-analyze)" {
  export HOME="$DEST_HOME"
  export MUSIC_INGEST_REPO="$REPO_ROOT"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" prepare --force-analyze
  [ "$status" -ne 0 ]
  [[ "$output" == *"force-analyze"* ]]
}

@test "successful synthetic import freezes new IDs, retains originals, and never enriches" {
  ingest_fixture success
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -eq 0 ]
  grep -q '^ids=101$' "$DEST_HOME/.local/share/music-ingest/verified-imports.log"
  [ -f "$DEST_HOME/Soulseek Downloads/complete/uploader/Album/track.mp3" ]
  [ -f "$DEST_HOME/Music/Library/MP3/verified.mp3" ]
  [ "$(grep -c '^import ' "$STUB_CALLS")" -eq 1 ]
  ! grep -Eq 'fetchart|embedart|lyrics|mbsync' "$STUB_CALLS"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -eq 0 ]
  [ "$(grep -c '^import ' "$STUB_CALLS")" -eq 1 ]
}

@test "an old same-size Library ID cannot become the new import cohort" {
  ingest_fixture success
  printf '100\n' >"$STUB_IDS"
  printf 'synthetic audio\n' >"$DEST_HOME/Music/Library/MP3/existing.mp3"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -eq 0 ]
  grep -q '^ids=101$' "$DEST_HOME/.local/share/music-ingest/verified-imports.log"
  ! grep -q '^ids=100' "$DEST_HOME/.local/share/music-ingest/verified-imports.log"
  [ -f "$DEST_HOME/Soulseek Downloads/complete/uploader/Album/track.mp3" ]
}

@test "same-size in-place audio edit invalidates seen fingerprint" {
  ingest_fixture success
  local src="$DEST_HOME/Soulseek Downloads/complete/uploader/Album/track.mp3"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -eq 0 ]
  printf 'synthetic AUDIO\n' >"$src"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -eq 0 ]
  grep -q '^ids=102$' "$DEST_HOME/.local/share/music-ingest/verified-imports.log"
  [ "$(grep -c '^import ' "$STUB_CALLS")" -eq 2 ]
}

@test "sidecar addition, same-size edit, and removal never reimport unchanged audio" {
  ingest_fixture success
  local sidecar="$DEST_HOME/Soulseek Downloads/complete/uploader/Album/cover.jpg"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -eq 0 ]
  printf 'art one\n' >"$sidecar"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -eq 0 ]
  [[ "$output" == *"sidecars changed (proposal only"* ]]
  printf 'art two\n' >"$sidecar"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -eq 0 ]
  rm "$sidecar"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -eq 0 ]
  [ "$(grep -c '^import ' "$STUB_CALLS")" -eq 1 ]
  [ "$(grep -c '^ids=' "$DEST_HOME/.local/share/music-ingest/verified-imports.log")" -eq 1 ]
}

@test "changed multi-track unit cannot reimport unchanged tracks" {
  ingest_fixture success
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -eq 0 ]
  printf 'synthetic second audio\n' >"$DEST_HOME/Soulseek Downloads/complete/uploader/Album/second.mp3"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -ne 0 ]
  [[ "$output" == *"audio changed in previously verified multi-track unit"* ]]
  [ "$(grep -c '^import ' "$STUB_CALLS")" -eq 1 ]
}

@test "removing one track from a verified multi-track unit cannot duplicate survivor" {
  ingest_fixture multi
  local dir="$DEST_HOME/Soulseek Downloads/complete/uploader/Album"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -eq 0 ]
  grep -q '^ids=101,102$' "$DEST_HOME/.local/share/music-ingest/verified-imports.log"
  rm "$dir/second.mp3"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -ne 0 ]
  [[ "$output" == *"audio changed in previously verified multi-track unit"* ]]
  [ "$(grep -c '^import ' "$STUB_CALLS")" -eq 1 ]
}

@test "legacy all-file receipt migrates only when exact unit still matches" {
  ingest_fixture success
  local dir="$DEST_HOME/Soulseek Downloads/complete/uploader/Album"
  local src="$dir/track.mp3"
  local state="$DEST_HOME/.local/share/music-ingest"
  local source_hash old_key
  mkdir -p "$state"
  source_hash="$(/usr/bin/shasum -a 256 "$src")"
  old_key="$(printf '%s\t%q\n' "${source_hash%% *}" "$src" | /usr/bin/shasum -a 256)"
  printf '%s\n' "${old_key%% *}" >"$state/seen.log"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -eq 0 ]
  grep -q '^audio-v2:' "$state/seen.log"
  printf 'new artwork\n' >"$dir/cover.jpg"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -eq 0 ]
  [ ! -s "$STUB_IDS" ]
  ! grep -q '^import ' "$STUB_CALLS"
}

@test "old receipt with only a changed sidecar fails closed before any import" {
  ingest_fixture success
  local dir="$DEST_HOME/Soulseek Downloads/complete/uploader/Album"
  local src="$dir/track.mp3"
  local sidecar="$dir/cover.jpg"
  local state="$DEST_HOME/.local/share/music-ingest"
  local audio_hash sidecar_hash old_key
  mkdir -p "$state"
  printf 'art one\n' >"$sidecar"
  audio_hash="$(/usr/bin/shasum -a 256 "$src")"
  sidecar_hash="$(/usr/bin/shasum -a 256 "$sidecar")"
  old_key="$(printf '%s\t%q\n%s\t%q\n' "${audio_hash%% *}" "$src" "${sidecar_hash%% *}" "$sidecar" | LC_ALL=C sort | /usr/bin/shasum -a 256)"
  printf '%s\n' "${old_key%% *}" >"$state/seen.log"
  printf 'art two\n' >"$sidecar"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -ne 0 ]
  [[ "$output" == *"legacy seen state cannot identify changed unit"* ]]
  ! grep -q '^audio-v2:' "$state/seen.log"
  ! grep -q '^import ' "$STUB_CALLS"
}

@test "ID or path baseline read failure leaves no phantom pending import" {
  ingest_fixture baseline-error
  local mode
  for mode in baseline-error baseline-path-error; do
    export STUB_MODE="$mode"
    run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
    [ "$status" -ne 0 ]
    [[ "$output" == *"no import started"* ]]
    [ -z "$(find "$DEST_HOME/.local/share/music-ingest/pending-imports" -type f -name 'unit.*' -print -quit)" ]
  done
  ! grep -q '^import ' "$STUB_CALLS"
}

@test "new IDs pointing to unrelated bytes are not accepted as imported sources" {
  ingest_fixture wrong-copy
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -ne 0 ]
  [[ "$output" == *"ambiguous/partial import"* ]]
  [ -n "$(find "$DEST_HOME/.local/share/music-ingest/pending-imports" -type f -name 'unit.*' -print -quit)" ]
  [ -f "$DEST_HOME/Soulseek Downloads/complete/uploader/Album/track.mp3" ]
  [ ! -f "$DEST_HOME/.local/share/music-ingest/seen.log" ]
}

@test "failed and partial imports retain marker and block all subsequent writes" {
  ingest_fixture partial
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -ne 0 ]
  [ -f "$DEST_HOME/Soulseek Downloads/complete/uploader/Album/track.mp3" ]
  [ -n "$(find "$DEST_HOME/.local/share/music-ingest/pending-imports" -type f -name 'unit.*' -print -quit)" ]
  ! grep -Eq 'fetchart|embedart|lyrics|mbsync' "$STUB_CALLS"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -ne 0 ]
  [[ "$output" == *"unresolved import marker"* ]]
  [ "$(grep -c '^import ' "$STUB_CALLS")" -eq 1 ]
}

@test "zero-ID success and interrupted import fail closed" {
  ingest_fixture noids
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -ne 0 ]
  [[ "$output" == *"ambiguous/partial import"* ]]
  [ -f "$DEST_HOME/Soulseek Downloads/complete/uploader/Album/track.mp3" ]
  rm -rf "$DEST_HOME/.local/share/music-ingest/pending-imports"
  export STUB_MODE=interrupt
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -ne 0 ]
  [ -n "$(find "$DEST_HOME/.local/share/music-ingest/pending-imports" -type f -name 'unit.*' -print -quit)" ]
}

@test "shared writer lock excludes ingest; catalog and enrich apply are disabled" {
  ingest_fixture success
  local lock="$DEST_HOME/.local/share/music-ingest/music-writer.lock"
  mkdir -p "$(dirname "$lock")"
  flock "$lock" -c 'sleep 4' &
  local locker=$!
  sleep 0.2
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" ingest
  [ "$status" -ne 0 ]
  [[ "$output" == *"already running"* ]]
  ! grep -q '^import ' "$STUB_CALLS"
  wait "$locker"
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" enrich --apply
  [ "$status" -ne 0 ]
  run "$REPO_ROOT/rig/home/dot_local/bin/executable_music-ingest" catalog --apply "$DEST_HOME/Music/Library/MP3"
  [ "$status" -ne 0 ]
  [[ "$output" == *"catalog --apply is disabled"* ]]
}

@test "ingest plist watches complete inbox and invokes ingest" {
  run rg -q 'Soulseek Downloads/complete' "$REPO_ROOT/rig/home/Library/LaunchAgents/com.wyattowalsh.music-ingest.plist.tmpl"
  [ "$status" -eq 0 ]
  run rg -q '<string>ingest</string>' "$REPO_ROOT/rig/home/Library/LaunchAgents/com.wyattowalsh.music-ingest.plist.tmpl"
  [ "$status" -eq 0 ]
}
