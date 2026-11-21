#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RUNNER="$REPO_ROOT/rig/home/dot_local/bin/executable_media-grab"
  LAUNCHER="$REPO_ROOT/rig/home/dot_local/libexec/media-grab/executable_launch-media-grab"
  LIBEXEC="$REPO_ROOT/rig/home/dot_local/libexec/media-grab"
  ASSETS="$REPO_ROOT/rig/home/dot_local/share/media-grab"
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  MOCK_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TEST_HOME" "$MOCK_BIN"
}

make_mock_runtime() {
  cat > "$MOCK_BIN/yt-dlp" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"${MOCK_ARGS:?}"
count_file="${MOCK_COUNT:?}"
count=0
[[ ! -f "$count_file" ]] || count="$(cat "$count_file")"
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
if [[ "${MOCK_AUTH_FAIL_ONCE:-0}" == 1 && "$count" == 1 ]]; then
  printf '%s\n' "ERROR: Sign in to confirm you're not a bot" >&2
  exit 1
fi
exit 0
SH
  for command_name in ffmpeg ffprobe deno open osascript; do
    cat > "$MOCK_BIN/$command_name" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  done
  chmod +x "$MOCK_BIN"/*
}

@test "shell sources parse" {
  run bash -n "$RUNNER" "$LAUNCHER" "$LIBEXEC"/media-grab-{config,install,runtime,modes}
  [ "$status" -eq 0 ]
}

@test "version is consistent" {
  run "$RUNNER" --version
  [ "$status" -eq 0 ]
  [ "$output" = "$(tr -d '[:space:]' <"$ASSETS/VERSION")" ]
  grep -Fq 'property appVersion : "1.3.0"' "$ASSETS/MediaGrab.applescript"
}

@test "install defaults to dry-run and writes nothing" {
  run env HOME="$TEST_HOME" MEDIAGRAB_REPO="$REPO_ROOT" "$RUNNER" install
  [ "$status" -eq 0 ]
  [[ "$output" == *"MediaGrab install plan"* ]]
  [ ! -e "$TEST_HOME/Applications/MediaGrab.app" ]
  [ ! -e "$TEST_HOME/Desktop/MediaGrab.app" ]
}

@test "maximum video delegates format ranking to yt-dlp" {
  make_mock_runtime
  args="$BATS_TEST_TMPDIR/video.args"; count="$BATS_TEST_TMPDIR/video.count"
  run env HOME="$TEST_HOME" PATH="$MOCK_BIN:/usr/bin:/bin" MOCK_ARGS="$args" MOCK_COUNT="$count" "$RUNNER" video 'https://example.test/video'
  [ "$status" -eq 0 ]
  ! grep -Fxq -- '--format' "$args"
  grep -Fxq -- '--merge-output-format' "$args"
  grep -Fxq -- 'mkv' "$args"
  grep -Fxq -- '--no-remote-components' "$args"
}

@test "English video uses the explicit language selector" {
  make_mock_runtime
  args="$BATS_TEST_TMPDIR/en.args"; count="$BATS_TEST_TMPDIR/en.count"
  run env HOME="$TEST_HOME" PATH="$MOCK_BIN:/usr/bin:/bin" MOCK_ARGS="$args" MOCK_COUNT="$count" "$RUNNER" video-en 'https://example.test/video'
  [ "$status" -eq 0 ]
  grep -Fxq -- 'bv+ba[language^=en]/b[language^=en]/bv*+ba/b' "$args"
}

@test "authentication retry is narrow and local" {
  make_mock_runtime
  args="$BATS_TEST_TMPDIR/auth.args"; count="$BATS_TEST_TMPDIR/auth.count"
  run env HOME="$TEST_HOME" PATH="$MOCK_BIN:/usr/bin:/bin" MOCK_ARGS="$args" MOCK_COUNT="$count" MOCK_AUTH_FAIL_ONCE=1 "$RUNNER" video 'https://example.test/private'
  [ "$status" -eq 0 ]
  [ "$(cat "$count")" -eq 2 ]
  grep -Fxq -- '--cookies-from-browser' "$args"
  grep -Fxq -- 'brave' "$args"
  ! grep -Eq '(^|[^0-9])403([^0-9]|$)' "$RUNNER"
}

@test "archive modes prevent raw info JSON embedding" {
  grep -Fq -- '--no-embed-info-json' "$RUNNER"
  grep -Fq -- '--clean-info-json' "$RUNNER"
  grep -Fq -- '--no-clean-info-json' "$RUNNER"
  grep -Fq -- '--no-embed-subs' "$RUNNER"
}

@test "dangerous legacy policy is absent" {
  ! grep -Fq -- '--sponsorblock-remove' "$RUNNER"
  ! grep -Fq -- '--no-part' "$RUNNER"
  ! grep -Fq -- '--remote-components ejs:github' "$RUNNER"
}

@test "humorous icon is tracked as reproducible SVG" {
  grep -Fq '>yoink<' "$ASSETS/MediaGrab-icon.svg"
  grep -Fq '<svg' "$ASSETS/MediaGrab-icon.svg"
}

@test "optional linters accept executable sources" {
  if command -v shellcheck >/dev/null 2>&1; then
    run shellcheck "$RUNNER" "$LAUNCHER" "$LIBEXEC"/media-grab-{config,install,runtime,modes}
    [ "$status" -eq 0 ]
  fi
  if command -v shfmt >/dev/null 2>&1; then
    run shfmt -d -i 2 -ci -bn "$RUNNER" "$LAUNCHER" "$LIBEXEC"/media-grab-{config,install,runtime,modes}
    [ "$status" -eq 0 ]
  fi
}
