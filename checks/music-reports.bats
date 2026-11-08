#!/usr/bin/env bats
# Offline music inventory and candidate export; never reads the live library.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/music-reports-bats.XXXXXX")"
  LIBRARY="$SANDBOX/Library"
  mkdir -p "$LIBRARY/FLAC/Artist" "$LIBRARY/Incoming/review"
  printf 'base\n' >"$LIBRARY/FLAC/Artist/Song.flac"
  printf 'copy\n' >"$LIBRARY/FLAC/Artist/Song.1.flac"
  printf 'other\n' >"$LIBRARY/FLAC/Artist/Other.flac"
  printf 'ignored\n' >"$LIBRARY/Incoming/review/Ignore.1.flac"
}

teardown() {
  /bin/rm -rf -- "$SANDBOX"
}

@test "hygiene report reads files without writing to library" {
  before="$(find "$LIBRARY" -type f -print | LC_ALL=C sort | while IFS= read -r file; do cksum "$file"; done)"
  run uv run python "$REPO_ROOT/checks/music-reports.py" hygiene --library "$LIBRARY" --beets-db "$SANDBOX/missing.db"
  [ "$status" -eq 0 ]
  [[ "$output" == *"audio files: 3"* ]]
  [[ "$output" == *"metadata gaps: not assessed (beets DB missing)"* ]]
  [ "$(find "$LIBRARY" -type f -print | LC_ALL=C sort | while IFS= read -r file; do cksum "$file"; done)" = "$before" ]
}

@test "duplicates export lists base and numbered candidate without altering audio" {
  run uv run python "$REPO_ROOT/checks/music-reports.py" duplicates --library "$LIBRARY"
  [ "$status" -eq 0 ]
  local csv="$LIBRARY/Incoming/review/same-format-duplicates.csv"
  [ -f "$csv" ]
  run uv run python - "$csv" <<'PY'
import csv
import sys
from pathlib import Path

with open(sys.argv[1], newline="") as source:
    rows = list(csv.DictReader(source))
assert {Path(row["path"]).name for row in rows} == {"Song.flac", "Song.1.flac"}
assert all(row["assessment"].startswith("review-only") for row in rows)
PY
  [ "$status" -eq 0 ]
  [ "$(<"$LIBRARY/FLAC/Artist/Song.flac")" = base ]
  [ "$(<"$LIBRARY/FLAC/Artist/Song.1.flac")" = copy ]
  [ "$(<"$LIBRARY/Incoming/review/Ignore.1.flac")" = ignored ]
}
