#!/usr/bin/env bash
# Static contract for music ingest + DJ-tag + Navidrome (no live launchctl/beets writes).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/rig/home/dot_local/bin/executable_music-ingest"
DJTAG="$ROOT/rig/home/dot_local/bin/executable_music-dj-tag"
PLIST_INGEST="$ROOT/rig/home/Library/LaunchAgents/com.wyattowalsh.music-ingest.plist.tmpl"
PLIST_NAVIDROME="$ROOT/rig/home/Library/LaunchAgents/com.wyattowalsh.navidrome.plist.tmpl"
BEETS="$ROOT/rig/home/private_dot_config/beets/config.yaml.tmpl"
NAVIDROME="$ROOT/rig/home/private_dot_config/navidrome/navidrome.toml.tmpl"
STIGNORE="$ROOT/rig/home/private_dot_config/music/stignore"
NDIGNORE="$ROOT/rig/home/private_dot_config/music/ndignore"
PICARD_PRESERVE="$ROOT/rig/home/private_dot_config/music/picard-preserve-tags.txt"
JUSTFILE="$ROOT/justfile"
DOCS="$ROOT/docs/content/docs/music.mdx"
MACOS="$ROOT/rig/bootstrap/macos.sh"

fail=0

fail_msg() {
  printf 'music-ingest: %s\n' "$*" >&2
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
require_file "$DJTAG" || true
require_file "$PLIST_INGEST" || true
require_file "$PLIST_NAVIDROME" || true
require_file "$BEETS" || true
require_file "$NAVIDROME" || true
require_file "$STIGNORE" || true
require_file "$NDIGNORE" || true
require_file "$PICARD_PRESERVE" || true
require_file "$JUSTFILE" || true
require_file "$DOCS" || true
require_file "$MACOS" || true

if [[ -f "$JUSTFILE" ]]; then
  if rg -q 'if \[\[ -x "\$\{HOME\}/\.local/bin/music-ingest" \]\]' "$JUSTFILE"; then
    fail_msg "justfile must not dest-first exec the home runner"
  fi
  if rg -F -q 'exec "${HOME}/.local/bin/music-ingest"' "$JUSTFILE"; then
    fail_msg "justfile must not exec dest runner"
  fi
  if ! rg -F -q 'executable_music-ingest" "$@"' "$JUSTFILE"; then
    fail_msg "just music-ingest must quote args so paths with spaces work"
  fi
  if ! rg -q '\[positional-arguments\]' "$JUSTFILE"; then
    fail_msg "just music-ingest must use [positional-arguments] so refine paths keep spaces"
  fi
  if ! rg -q 'MUSIC_INGEST_REPO' "$JUSTFILE"; then
    fail_msg "justfile install recipe must export MUSIC_INGEST_REPO"
  fi
  if ! rg -q '^music-hygiene:' "$JUSTFILE"; then
    fail_msg "justfile must expose the read-only music-hygiene report recipe"
  fi
  if rg -A40 '^music-hygiene:' "$JUSTFILE" | rg -q -- '--force|beet lyrics|beet remove'; then
    fail_msg "music-hygiene must stay a read-only report"
  fi
  if ! rg -q '^music-duplicates:' "$JUSTFILE"; then
    fail_msg "justfile must expose the read-only music-duplicates review export"
  fi
  if ! rg -A70 '^music-duplicates:' "$JUSTFILE" | rg -q 'Incoming/review'; then
    fail_msg "music-duplicates must export its review CSV under Incoming/review"
  fi
  if rg -A70 '^music-duplicates:' "$JUSTFILE" | rg -q -- '--force|beet lyrics|beet remove|rm -'; then
    fail_msg "music-duplicates must stay read-only and never delete"
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
  if ! rg -q 'iter_inbox_units' "$RUNNER"; then
    fail_msg "ingest must walk nested Soulseek album dirs"
  fi
  if rg -q 'find "\$complete" -mindepth 1 -maxdepth 1 -type d' "$RUNNER"; then
    fail_msg "ingest must not treat complete/* uploaders as albums"
  fi
  if rg -q 'skipping\|no match\|unmatched\|not found' "$RUNNER"; then
    fail_msg "ingest must not treat chroma/MB 'not found' log lines as a failed import"
  fi
  if ! rg -q 'cmd_refine' "$RUNNER" && ! rg -q 'refine)' "$RUNNER"; then
    fail_msg "runner must implement refine"
  fi
  if ! rg -F -q 'prepare)' "$RUNNER"; then
    fail_msg "runner must alias prepare to refine"
  fi
  if ! rg -q 'refuses --force-analyze' "$RUNNER"; then
    fail_msg "refine must refuse --force-analyze"
  fi
  if ! rg -q 'MUSIC_INGEST_INCLUDE_ICLOUD' "$RUNNER"; then
    fail_msg "refine must not hydrate iCloud unless opted in"
  fi
  if ! rg -q 'plist.tmpl' "$RUNNER"; then
    fail_msg "install must render dest plist from tmpl"
  fi
  if ! rg -F -q 'catalog)' "$RUNNER"; then
    fail_msg "runner must implement catalog"
  fi
  if ! rg -F -q 'enrich)' "$RUNNER"; then
    fail_msg "runner must implement enrich"
  fi
  if ! rg -q -- '--move --nocopy' "$RUNNER"; then
    fail_msg "catalog must --move Incoming staging (same-volume, no 2x disk)"
  fi
  if ! rg -F -q '"$BEET_BIN" import --quiet --copy' "$RUNNER"; then
    fail_msg "ingest must copy, retaining inbox originals until an independently gated cleanup"
  fi
  if rg -q 'src\.unlink|find "\$complete" -mindepth 1 -delete' "$RUNNER"; then
    fail_msg "ingest must never delete inbox copies before independently verified cleanup"
  fi
  if ! rg -q 'enrich_paths' "$RUNNER"; then
    fail_msg "ingest must enrich imported files via enrich_paths"
  fi
  if ! rg -q 'would enrich imported files' "$RUNNER"; then
    fail_msg "ingest dry-run must mention per-import enrich"
  fi
  if rg -q 'DJ-tag fill-if-missing on today' "$RUNNER"; then
    fail_msg "ingest must not DJ-tag the whole library on every WatchPaths fire"
  fi
  if ! rg -q 'beet_id_snapshot|verify_imported_ids' "$RUNNER"; then
    fail_msg "ingest must verify a frozen cohort of new beets IDs"
  fi
  if ! rg -q 'pending-imports|assert_no_pending_imports' "$RUNNER"; then
    fail_msg "ingest must refuse unresolved partial/interrupt markers"
  fi
  if ! rg -F -q 'dir_seen_key' "$RUNNER" || ! rg -F -q 'shasum -a 256 "$file"' "$RUNNER"; then
    fail_msg "seen key must hash direct file contents, not directory mtime"
  fi
  if ! rg -F -q 'dir_seen_key "$dir" audio' "$RUNNER" \
    || ! rg -F -q 'dir_seen_key "$dir" sidecar' "$RUNNER" \
    || ! rg -F -q 'audio-v2:' "$RUNNER" || ! rg -F -q 'sidecar-v1:' "$RUNNER" \
    || ! rg -F -q 'unit-v2:' "$RUNNER"; then
    fail_msg "audio identity must be independent of sidecars, with multi-track reimport guarded"
  fi
  if ! rg -F -q 'beet_path_snapshot' "$RUNNER" || ! rg -F -q 'source_hashes' "$RUNNER"; then
    fail_msg "ID verification must exclude preexisting paths and match source bytes"
  fi
  if ! rg -F -q 'music-writer.lock' "$RUNNER"; then
    fail_msg "ingest must use the shared writer lock"
  fi
  if ! rg -q 'enrich --apply is disabled' "$RUNNER" || ! rg -q 'catalog --apply is disabled' "$RUNNER"; then
    fail_msg "whole-library enrichment and unverified catalog imports must be disabled"
  fi
  if rg -q -- '-newermt|beet fetchart -q \|\| log|beet mbsync -M \|\| log' "$RUNNER"; then
    fail_msg "mtime-selected and masked enrichment writers are forbidden"
  fi
  if ! rg -q 'gdrive restore copy still running' "$RUNNER"; then
    fail_msg "catalog must refuse to run while rclone restore is in flight"
  fi
  if rg -q 'brew tap evanpurkhiser' "$RUNNER"; then
    fail_msg "do not add extra Homebrew taps for keyfinder-cli"
  fi
fi

if [[ -f "$DJTAG" ]]; then
  if rg -q '/Users/' "$DJTAG"; then
    fail_msg "dj-tag must not hardcode /Users/ paths"
  fi
  if ! rg -q 'GEOB' "$DJTAG" && ! rg -q 'SERATO' "$DJTAG"; then
    fail_msg "dj-tag must mention Serato/GEOB preservation"
  fi
  if ! rg -q 'INITIALKEY' "$DJTAG"; then
    fail_msg "dj-tag must dual-write INITIALKEY"
  fi
  if ! rg -q 'has_primary_key' "$DJTAG"; then
    fail_msg "dj-tag must refuse to replace occupied primary key text"
  fi
  if ! rg -F -q -- '--self-test' "$DJTAG"; then
    fail_msg "dj-tag must ship a --self-test for fill-if-missing"
  fi
  if ! rg -q 'CAMELOT_TO_NOTE' "$DJTAG"; then
    fail_msg "dj-tag must map Camelot back to musical key"
  fi
  if ! rg -q 'mismatch-kept' "$DJTAG"; then
    fail_msg "dj-tag must keep mismatched key/Camelot instead of overwriting"
  fi
  if ! rg -q 'will not prepend ID3' "$DJTAG"; then
    fail_msg "dj-tag must skip WAV/AIFF rather than prepend ID3"
  fi
  if ! rg -q 'st_blocks' "$DJTAG"; then
    fail_msg "dj-tag must treat zero-block iCloud placeholders as dataless"
  fi
  if ! rg -q 'parse_mix_version' "$DJTAG"; then
    fail_msg "dj-tag must parse hardstyle mix versions from title parentheticals"
  fi
  if ! rg -q 'MIXVERSION' "$DJTAG"; then
    fail_msg "dj-tag must write MIXVERSION fill-if-missing"
  fi
fi

if [[ -f "$PLIST_INGEST" ]]; then
  if ! rg -q 'WatchPaths' "$PLIST_INGEST"; then
    fail_msg "ingest plist must WatchPaths the complete inbox"
  fi
  if ! rg -q 'Soulseek Downloads/complete' "$PLIST_INGEST"; then
    fail_msg "ingest plist must watch Soulseek Downloads/complete"
  fi
  if ! rg -q '<string>ingest</string>' "$PLIST_INGEST"; then
    fail_msg "ingest plist must invoke ingest"
  fi
  if rg -q '/Users/' "$PLIST_INGEST"; then
    fail_msg "ingest plist must not hardcode /Users/ paths"
  fi
fi

if [[ -f "$PLIST_NAVIDROME" ]]; then
  if ! rg -q 'KeepAlive' "$PLIST_NAVIDROME"; then
    fail_msg "navidrome plist must KeepAlive"
  fi
  if ! rg -U -q '<key>ProcessType</key>\n[[:blank:]]*<string>Interactive</string>' "$PLIST_NAVIDROME"; then
    fail_msg "navidrome plist must use Interactive process policy for user-requested playback"
  fi
  if ! rg -q 'navidrome.toml' "$PLIST_NAVIDROME"; then
    fail_msg "navidrome plist must pass navidrome.toml"
  fi
  if rg -q '/Users/' "$PLIST_NAVIDROME"; then
    fail_msg "navidrome plist must not hardcode /Users/ paths"
  fi
fi

if [[ -f "$BEETS" ]]; then
  if ! rg -q 'from_scratch: no' "$BEETS"; then
    fail_msg "beets must set from_scratch: no"
  fi
  if ! rg -q 'quiet_fallback: asis' "$BEETS"; then
    fail_msg "beets quiet import must fall back to asis so tagged inbox copies into Library"
  fi
  if ! rg -q 'none_rec_action: asis' "$BEETS"; then
    fail_msg "beets none_rec_action must be asis (skip left the library empty)"
  fi
  if rg -q '%albumartist' "$BEETS"; then
    fail_msg "beets paths must use \$albumartist not %albumartist"
  fi
  if ! rg -q 'duplicate_action: keep' "$BEETS"; then
    fail_msg "beets must keep dual-format copies"
  fi
  if ! rg -q 'id3v23: no' "$BEETS"; then
    fail_msg "beets must write ID3v2.4"
  fi
  if ! rg -q 'keyfinder' "$BEETS"; then
    fail_msg "beets must enable keyfinder"
  fi
  if ! rg -q 'overwrite: no' "$BEETS"; then
    fail_msg "keyfinder must not overwrite existing keys"
  fi
  if rg -q 'acousticbrainz' "$BEETS"; then
    fail_msg "do not enable AcousticBrainz"
  fi
  if ! rg -q -- '- musicbrainz' "$BEETS"; then
    fail_msg "beets 2.13+ must enable the musicbrainz plugin (otherwise autotag has no MB source)"
  fi
  if ! rg -q 'genres: yes' "$BEETS"; then
    fail_msg "beets must import MusicBrainz genres"
  fi
  if ! rg -q 'coverart' "$BEETS"; then
    fail_msg "beets fetchart must use Cover Art Archive"
  fi
  if ! rg -A10 '^fetchart:' "$BEETS" | rg -q 'high_resolution: no'; then
    fail_msg "beets iTunes art must use the working 1200px mode, not the broken ultra-high endpoint"
  fi
  if ! rg -q 'ifempty: yes' "$BEETS"; then
    fail_msg "beets embedart must be ifempty (do not replace existing art)"
  fi
  if ! rg -A8 '^lyrics:' "$BEETS" | rg -q 'auto: no'; then
    fail_msg "beets lyrics auto must stay off; beets 2.14+ uses explicit post-import/manual network fetches"
  fi
  if ! rg -q 'lrclib' "$BEETS"; then
    fail_msg "beets lyrics must use LRCLib (not Genius scrape)"
  fi
  if ! rg -q 'beatport: yes' "$BEETS"; then
    fail_msg "beets must store Beatport IDs from MusicBrainz URL relationships"
  fi
  if rg -q '/Users/' "$BEETS"; then
    fail_msg "beets config must not hardcode /Users/ paths"
  fi
fi

if [[ -f "$NAVIDROME" ]]; then
  if ! rg -q 'Music/Library' "$NAVIDROME"; then
    fail_msg "navidrome must scan Music/Library not ~/Music"
  fi
  if rg -q 'DevAutoCreateAdminPassword' "$NAVIDROME"; then
    fail_msg "navidrome config must not embed admin passwords"
  fi
  if ! rg -F -x -q 'Scanner.Schedule = 0' "$NAVIDROME"; then
    fail_msg "navidrome periodic scans must stay off; the 5s watcher covers library changes and explicit full scans cover the rest"
  fi
  if ! rg -F -x -q "Scanner.WatcherWait = '5s'" "$NAVIDROME"; then
    fail_msg "navidrome must use the supported 5s scanner watcher wait"
  fi
  if rg -q '^Scanner\.WatcherEnabled[[:space:]]*=' "$NAVIDROME"; then
    fail_msg "navidrome must not use stale Scanner.WatcherEnabled"
  fi
  if ! rg -q "PurgeMissing = 'always'" "$NAVIDROME"; then
    fail_msg "navidrome must purge missing files so Incoming leftovers leave the catalog"
  fi
  if ! rg -F -x -q 'EnableExternalServices = true' "$NAVIDROME"; then
    fail_msg "navidrome must explicitly enable external services"
  fi
  if ! rg -F -x -q "Agents = 'deezer,listenbrainz'" "$NAVIDROME"; then
    fail_msg "navidrome must explicitly use Deezer and ListenBrainz agents"
  fi
  if ! rg -F -x -q "ArtistArtPriority = 'artist.*, album/artist.*, external'" "$NAVIDROME"; then
    fail_msg "navidrome artist art must prefer local files before external fallback"
  fi
  if ! rg -F -x -q "CoverArtPriority = 'embedded, cover.*, folder.*, front.*, albumart*, external'" "$NAVIDROME"; then
    fail_msg "navidrome cover art must prefer embedded/local files before external fallback"
  fi
  if ! rg -F -x -q "LyricsPriority = '.ttml,.yaml,.yml,.elrc,.lrc,.srt,.txt,embedded'" "$NAVIDROME"; then
    fail_msg "navidrome must use the explicit local/embedded lyrics priority"
  fi
  if ! rg -q "^ArtistArtPriority = '[^']*external'$" "$NAVIDROME"; then
    fail_msg "navidrome external artist art must remain the final fallback"
  fi
  if ! rg -q "^CoverArtPriority = '[^']*external'$" "$NAVIDROME"; then
    fail_msg "navidrome external cover art must remain the final fallback"
  fi
  if rg -q '/Users/' "$NAVIDROME"; then
    fail_msg "navidrome config must not hardcode /Users/ paths"
  fi
fi

if [[ -f "$STIGNORE" ]]; then
  if ! rg -q 'Incoming/review' "$STIGNORE"; then
    fail_msg "stignore must exclude Incoming/review from phone sync"
  fi
fi

if [[ -f "$NDIGNORE" ]]; then
  if ! rg -q 'Incoming/' "$NDIGNORE"; then
    fail_msg "ndignore must exclude Incoming from Navidrome catalog"
  fi
fi

if [[ -f "$DOCS" ]]; then
  if ! rg -q 'just music-ingest' "$DOCS"; then
    fail_msg "music.mdx must document just music-ingest"
  fi
  if ! rg -q 'refine --apply' "$DOCS"; then
    fail_msg "music.mdx must document refine --apply"
  fi
  if ! rg -q 'Camelot' "$DOCS"; then
    fail_msg "music.mdx must document Camelot"
  fi
  if ! rg -q 'prepare' "$DOCS"; then
    fail_msg "music.mdx must document prepare"
  fi
  if ! rg -q 'catalog --apply' "$DOCS"; then
    fail_msg "music.mdx must document catalog --apply"
  fi
  if ! rg -q 'Cover Art Archive' "$DOCS"; then
    fail_msg "music.mdx must document Cover Art Archive art"
  fi
  if ! rg -q 'MIXVERSION' "$DOCS"; then
    fail_msg "music.mdx must document MIXVERSION for DJ mix versions"
  fi
  if ! rg -q 'Beatport' "$DOCS"; then
    fail_msg "music.mdx must document Beatport IDs"
  fi
  if rg -q 'TKEY normalized to a note' "$DOCS"; then
    fail_msg "music.mdx must not rewrite Camelot stored in TKEY"
  fi
  if rg -q '/Users/' "$DOCS"; then
    fail_msg "music.mdx must not hardcode /Users/ paths"
  fi
  if ! rg -q 'Synctrain' "$DOCS"; then
    fail_msg "music.mdx must document Synctrain"
  fi
  if ! rg -q 'Shelv' "$DOCS"; then
    fail_msg "music.mdx must document Shelv"
  fi
  if ! rg -q 'asis' "$DOCS"; then
    fail_msg "music.mdx must document beets asis quiet fallback"
  fi
fi

if [[ -f "$MACOS" ]]; then
  if ! rg -q 'executable_music-ingest' "$MACOS"; then
    fail_msg "macos.sh must install music-ingest when the runner source exists"
  fi
fi

if [[ "$fail" -ne 0 ]]; then
  printf 'music-ingest: FAIL\n' >&2
  exit 1
fi

printf 'music-ingest: ok\n'
