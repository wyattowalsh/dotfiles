#!/usr/bin/env bats
# Offline apply/doctor/restore coverage for pinned IINA plugin and shader installers.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/iina-installers-bats.XXXXXX")"
  DOWNLOADS="$SANDBOX/downloads"
  FAKE_BIN="$SANDBOX/bin"
  mkdir -p "$DOWNLOADS" "$FAKE_BIN"
  export FAKE_DOWNLOADS="$DOWNLOADS"
  export IINA_OPERATION_LOCK="$SANDBOX/iina-operation.lock"
  export PATH="$FAKE_BIN:$PATH"

  cat >"$FAKE_BIN/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
url=""
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      out="$2"
      shift 2
      ;;
    http://* | https://*)
      url="$1"
      shift
      ;;
    *) shift ;;
  esac
done
[[ -n "$url" && -n "$out" ]]
cp "$FAKE_DOWNLOADS/${url##*/}" "$out"
SH
  cat >"$FAKE_BIN/pgrep" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/pgrep"
}

teardown() {
  rm -rf "$SANDBOX"
}

sha256() {
  shasum -a 256 "$1" | cut -d ' ' -f 1
}

make_shader_fixture() {
  local anime_dir="$SANDBOX/anime"
  mkdir -p "$anime_dir"
  printf '%s\n' '//!HOOK MAIN' '//!BIND HOOKED' 'vec4 hook() { return HOOKED_tex(HOOKED_pos); }' \
    >"$anime_dir/Anime4K_Test.glsl"
  printf '%s\n' '//!HOOK MAIN' '//!BIND HOOKED' 'vec4 hook() { return HOOKED_tex(HOOKED_pos); }' \
    >"$DOWNLOADS/FSRCNNX_Test.glsl"
  (
    cd "$anime_dir"
    zip -q "$DOWNLOADS/Anime4K_Test.zip" Anime4K_Test.glsl
  )

  local anime_zip_sha anime_file_sha fsrcnnx_sha
  anime_zip_sha="$(sha256 "$DOWNLOADS/Anime4K_Test.zip")"
  anime_file_sha="$(sha256 "$anime_dir/Anime4K_Test.glsl")"
  fsrcnnx_sha="$(sha256 "$DOWNLOADS/FSRCNNX_Test.glsl")"
  cat >"$SANDBOX/shaders-pin.json" <<JSON
{
  "version": 1,
  "dest": ".config/iina-mpv/shaders",
  "sources": [
    {
      "id": "anime4k",
      "repo": "test/Anime4K",
      "tag": "v1",
      "asset": "Anime4K_Test.zip",
      "sha256": "$anime_zip_sha",
      "files": [{"name": "Anime4K_Test.glsl", "sha256": "$anime_file_sha"}]
    },
    {
      "id": "fsrcnnx",
      "repo": "test/FSRCNNX",
      "tag": "v1",
      "assets": [{"name": "FSRCNNX_Test.glsl", "sha256": "$fsrcnnx_sha"}]
    }
  ]
}
JSON
}

make_plugin_fixture() {
  local id version asset dest dir sha rows
  rows=(
    $'io.iina.ytdl\t0.9.10\tiina-plugin-ytdl-0.9.10.iinaplgz\tio.iina.ytdl.iinaplugin'
    $'io.iina.opensub\t0.9.6\tiina-plugin-opensub-0.9.6.iinaplgz\tio.iina.opensub.iinaplugin'
    $'io.iina.user-script\t0.9.3\tiina-plugin-userscript-0.9.3.iinaplgz\tio.iina.user-script.iinaplugin'
  )
  printf '%s\n' '{"version":1,"plugins":[' >"$SANDBOX/plugins-pin.json"
  local first=1
  for rows in "${rows[@]}"; do
    IFS=$'\t' read -r id version asset dest <<<"$rows"
    dir="$SANDBOX/package-$id"
    mkdir -p "$dir"
    printf '{"name":"Test","identifier":"%s","version":"%s","entry":"index.js"}\n' "$id" "$version" >"$dir/Info.json"
    printf '%s\n' '"use strict";' >"$dir/index.js"
    local official_repo official_package
    case "$id" in
      io.iina.ytdl) official_repo=iina/plugin-online-media; official_package=iina-plugin-ytdl ;;
      io.iina.opensub) official_repo=iina/plugin-opensub; official_package=iina-plugin-opensub ;;
      io.iina.user-script) official_repo=iina/plugin-userscript; official_package=iina-plugin-userscript ;;
    esac
    asset="$official_package-$version.iinaplgz"
    (
      cd "$dir"
      zip -q -r "$DOWNLOADS/$asset" Info.json index.js
    )
    sha="$(sha256 "$DOWNLOADS/$asset")"
    if [[ "$first" -eq 0 ]]; then printf ',\n' >>"$SANDBOX/plugins-pin.json"; fi
    first=0
    printf '{"identifier":"%s","name":"Test","repo":"%s","tag":"v%s","version":"%s","asset":"%s","sha256":"%s","dest":"%s"}' \
      "$id" "$official_repo" "$version" "$version" "$asset" "$sha" "$dest" >>"$SANDBOX/plugins-pin.json"
  done
  printf '%s\n' ']}' >>"$SANDBOX/plugins-pin.json"
}

@test "installers ignore poisoned cwd and PYTHONPATH for pins, archives, and backups" {
  make_plugin_fixture
  make_shader_fixture
  local poison="$SANDBOX/poison"
  mkdir -p "$poison"
  printf 'raise RuntimeError("loaded planted json.py")\n' >"$poison/json.py"
  printf 'raise RuntimeError("loaded planted zipfile.py")\n' >"$poison/zipfile.py"
  export PYTHONPATH="$poison"
  export IINA_PLUGINS_PIN="$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_DEST="$SANDBOX/plugins"
  export IINA_PLUGINS_STATE="$SANDBOX/plugin-state"
  export IINA_SHADERS_PIN="$SANDBOX/shaders-pin.json"
  export IINA_SHADERS_DEST_ROOT="$SANDBOX/iina-mpv"
  export IINA_SHADERS_STATE="$SANDBOX/shader-state"

  run bash -c 'cd "$1" && exec "$2" install --apply' _ "$poison" "$REPO_ROOT/checks/iina-plugins.sh"
  [ "$status" -eq 0 ]
  [ -f "$SANDBOX/plugins/io.iina.ytdl.iinaplugin/Info.json" ]
  run bash -c 'cd "$1" && exec "$2" restore --dry-run' _ "$poison" "$REPO_ROOT/checks/iina-plugins.sh"
  [ "$status" -eq 0 ]
  run bash -c 'cd "$1" && exec "$2" install --apply' _ "$poison" "$REPO_ROOT/checks/iina-shaders.sh"
  [ "$status" -eq 0 ]
  [ -f "$SANDBOX/iina-mpv/shaders/Anime4K_Test.glsl" ]
  run bash -c 'cd "$1" && exec "$2" restore --dry-run' _ "$poison" "$REPO_ROOT/checks/iina-shaders.sh"
  [ "$status" -eq 0 ]
}

@test "installer previews fail closed without uv" {
  make_plugin_fixture
  make_shader_fixture
  export IINA_PLUGINS_PIN="$SANDBOX/plugins-pin.json"
  export IINA_SHADERS_PIN="$SANDBOX/shaders-pin.json"
  run /usr/bin/env PATH=/usr/bin:/bin "$REPO_ROOT/checks/iina-plugins.sh" preview
  [ "$status" -ne 0 ]
  [[ "$output" == *"required tool unavailable: uv"* ]]
  run /usr/bin/env PATH=/usr/bin:/bin "$REPO_ROOT/checks/iina-shaders.sh" preview
  [ "$status" -ne 0 ]
  [[ "$output" == *"required tool unavailable: uv"* ]]
}

@test "shared IINA lock blocks optional installer mutations" {
  make_shader_fixture
  make_plugin_fixture
  exec 7>"$IINA_OPERATION_LOCK"
  flock -n 7
  export IINA_SHADERS_PIN="$SANDBOX/shaders-pin.json"
  export IINA_SHADERS_DEST_ROOT="$SANDBOX/iina-mpv"
  export IINA_SHADERS_STATE="$SANDBOX/shader-state"
  run "$REPO_ROOT/checks/iina-shaders.sh" install --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"another IINA operation is running"* ]]
  export IINA_PLUGINS_PIN="$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_DEST="$SANDBOX/plugins"
  export IINA_PLUGINS_STATE="$SANDBOX/plugin-state"
  run "$REPO_ROOT/checks/iina-plugins.sh" install --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"another IINA operation is running"* ]]
  [ ! -e "$SANDBOX/plugins/io.iina.ytdl.iinaplugin" ]
  [ ! -e "$SANDBOX/iina-mpv/shaders" ]
  flock -u 7
  exec 7>&-
}

@test "oversized pinned shader archive is rejected before extraction" {
  make_shader_fixture
  UV_NO_PROJECT=1 uv run --offline --no-project python -I - "$DOWNLOADS/Anime4K_Test.zip" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1], 'a') as archive:
    archive.writestr('unselected-large.glsl', 'x' * (256 * 1024 * 1024 + 1), compress_type=zipfile.ZIP_DEFLATED)
PY
  local altered_sha
  altered_sha="$(sha256 "$DOWNLOADS/Anime4K_Test.zip")"
  /usr/bin/perl -0pi -e "s/\"sha256\": \"[0-9a-f]{64}\",\n      \"files\"/\"sha256\": \"$altered_sha\",\n      \"files\"/" "$SANDBOX/shaders-pin.json"
  export IINA_SHADERS_PIN="$SANDBOX/shaders-pin.json"
  export IINA_SHADERS_DEST_ROOT="$SANDBOX/iina-mpv"
  export IINA_SHADERS_STATE="$SANDBOX/shader-state"
  run "$REPO_ROOT/checks/iina-shaders.sh" install --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"oversized shader archive entry"* ]]
  [ ! -e "$SANDBOX/iina-mpv/shaders" ]
}

@test "shader archive with traversal is rejected before extraction" {
  make_shader_fixture
  UV_NO_PROJECT=1 uv run --offline --no-project python -I - "$DOWNLOADS/Anime4K_Test.zip" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1], "a") as archive:
    archive.writestr("../escape.glsl", "outside")
PY
  local escaped_sha
  escaped_sha="$(sha256 "$DOWNLOADS/Anime4K_Test.zip")"
  /usr/bin/perl -0pi -e "s/\"sha256\": \"[0-9a-f]{64}\",\n      \"files\"/\"sha256\": \"$escaped_sha\",\n      \"files\"/" "$SANDBOX/shaders-pin.json"
  export IINA_SHADERS_PIN="$SANDBOX/shaders-pin.json"
  export IINA_SHADERS_DEST_ROOT="$SANDBOX/iina-mpv"
  export IINA_SHADERS_STATE="$SANDBOX/shader-state"
  run "$REPO_ROOT/checks/iina-shaders.sh" install --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsafe archive entry"* ]]
  [ ! -e "$SANDBOX/escape.glsl" ]
  [ ! -e "$SANDBOX/iina-mpv/shaders" ]
}

@test "shader install failure restores old directory and skips incomplete newer snapshot" {
  make_shader_fixture
  local dest="$SANDBOX/iina-mpv" state="$SANDBOX/shader-state"
  mkdir -p "$dest/shaders"
  printf 'old shader\n' >"$dest/shaders/old.glsl"
  cat >"$FAKE_BIN/mv" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"download."*"/shaders"* ]]; then exit 91; fi
exec /bin/mv "$@"
SH
  chmod +x "$FAKE_BIN/mv"
  export IINA_SHADERS_PIN="$SANDBOX/shaders-pin.json"
  export IINA_SHADERS_DEST_ROOT="$dest"
  export IINA_SHADERS_STATE="$state"
  run "$REPO_ROOT/checks/iina-shaders.sh" install --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"interrupted install recovered"* ]]
  [ -f "$dest/shaders/old.glsl" ]
  /bin/rm -f "$FAKE_BIN/mv"
  mkdir -p "$state/99999999T999999Z.incomplete"
  run "$REPO_ROOT/checks/iina-shaders.sh" restore
  [ "$status" -eq 0 ]
  [[ "$output" != *"99999999T999999Z.incomplete"* ]]
}

@test "shader installer applies, detects drift, and restores the prior directory" {
  command -v zip >/dev/null || skip "zip unavailable"
  make_shader_fixture
  local dest="$SANDBOX/iina-mpv"
  local state="$SANDBOX/shader-state"
  mkdir -p "$dest/shaders"
  printf '%s\n' 'old shader' >"$dest/shaders/old.glsl"

  export IINA_SHADERS_PIN="$SANDBOX/shaders-pin.json"
  export IINA_SHADERS_DEST_ROOT="$dest"
  export IINA_SHADERS_STATE="$state"

  run "$REPO_ROOT/checks/iina-shaders.sh" install --apply
  [ "$status" -eq 0 ]
  [ -f "$dest/shaders/Anime4K_Test.glsl" ]
  [ -f "$dest/shaders/FSRCNNX_Test.glsl" ]
  [ ! -f "$dest/shaders/old.glsl" ]

  run "$REPO_ROOT/checks/iina-shaders.sh" doctor
  [ "$status" -eq 0 ]
  printf '%s\n' 'tampered' >"$dest/shaders/Anime4K_Test.glsl"
  run "$REPO_ROOT/checks/iina-shaders.sh" doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"drift anime4k/Anime4K_Test.glsl"* ]]

  run "$REPO_ROOT/checks/iina-shaders.sh" restore --apply
  [ "$status" -eq 0 ]
  [ -f "$dest/shaders/old.glsl" ]
  [[ "$(cat "$dest/shaders/old.glsl")" == "old shader" ]]
}

@test "oversized pinned plugin archive is rejected before extraction" {
  make_plugin_fixture
  UV_NO_PROJECT=1 uv run --offline --no-project python -I - "$DOWNLOADS/iina-plugin-ytdl-0.9.10.iinaplgz" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1], 'a') as archive:
    archive.writestr('unselected-large.bin', 'x' * (64 * 1024 * 1024 + 1), compress_type=zipfile.ZIP_DEFLATED)
PY
  local altered_sha
  altered_sha="$(sha256 "$DOWNLOADS/iina-plugin-ytdl-0.9.10.iinaplgz")"
  /usr/bin/perl -0pi -e "s/[0-9a-f]{64}(?=\",\"dest\":\"io\.iina\.ytdl\.iinaplugin\")/$altered_sha/" "$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_PIN="$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_DEST="$SANDBOX/plugins"
  export IINA_PLUGINS_STATE="$SANDBOX/plugin-state"
  run "$REPO_ROOT/checks/iina-plugins.sh" install --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"oversized plugin archive entry"* ]]
  [ ! -e "$SANDBOX/plugins/io.iina.ytdl.iinaplugin" ]
}

@test "shader restore failure recovers prior set" {
  make_shader_fixture
  local dest="$SANDBOX/iina-mpv" state="$SANDBOX/shader-state"
  mkdir -p "$dest/shaders"
  printf 'old shader\n' >"$dest/shaders/old.glsl"
  export IINA_SHADERS_PIN="$SANDBOX/shaders-pin.json"
  export IINA_SHADERS_DEST_ROOT="$dest"
  export IINA_SHADERS_STATE="$state"
  run "$REPO_ROOT/checks/iina-shaders.sh" install --apply
  [ "$status" -eq 0 ]
  cat >"$FAKE_BIN/mv" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"staged-shaders"* ]]; then exit 91; fi
exec /bin/mv "$@"
SH
  chmod +x "$FAKE_BIN/mv"
  run "$REPO_ROOT/checks/iina-shaders.sh" restore --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"interrupted restore recovered"* ]]
  [ -f "$dest/shaders/Anime4K_Test.glsl" ]
  [ -f "$dest/shaders/FSRCNNX_Test.glsl" ]
  [ ! -e "$dest/shaders/old.glsl" ]
}

@test "official plugin archive with symlink is rejected before install" {
  make_plugin_fixture
  UV_NO_PROJECT=1 uv run --offline --no-project python -I - "$DOWNLOADS/iina-plugin-ytdl-0.9.10.iinaplgz" <<'PY'
import stat
import sys
import zipfile

info = zipfile.ZipInfo("shortcut")
info.create_system = 3
info.external_attr = (stat.S_IFLNK | 0o777) << 16
with zipfile.ZipFile(sys.argv[1], "a") as archive:
    archive.writestr(info, "../../outside")
PY
  local altered_sha
  altered_sha="$(sha256 "$DOWNLOADS/iina-plugin-ytdl-0.9.10.iinaplgz")"
  /usr/bin/perl -0pi -e "s/[0-9a-f]{64}(?=\",\"dest\":\"io\.iina\.ytdl\.iinaplugin\")/$altered_sha/" "$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_PIN="$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_DEST="$SANDBOX/plugins"
  export IINA_PLUGINS_STATE="$SANDBOX/plugin-state"
  run "$REPO_ROOT/checks/iina-plugins.sh" install --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsafe archive entry"* ]]
  [ ! -e "$SANDBOX/plugins/io.iina.ytdl.iinaplugin" ]
}

@test "plugin archive with unsupported Unix hardlink metadata is rejected before extraction" {
  make_plugin_fixture
  UV_NO_PROJECT=1 uv run --offline --no-project python -I - "$DOWNLOADS/iina-plugin-ytdl-0.9.10.iinaplgz" <<'PY'
import struct
import sys
import zipfile

info = zipfile.ZipInfo("shortcut")
info.create_system = 3
info.external_attr = (0o100644 << 16)
info.extra = struct.pack("<HH", 0x756e, 0)  # ASi Unix metadata can encode links.
with zipfile.ZipFile(sys.argv[1], "a") as archive:
    archive.writestr(info, "outside")
PY
  local altered_sha
  altered_sha="$(sha256 "$DOWNLOADS/iina-plugin-ytdl-0.9.10.iinaplgz")"
  /usr/bin/perl -0pi -e "s/[0-9a-f]{64}(?=\",\"dest\":\"io\.iina\.ytdl\.iinaplugin\")/$altered_sha/" "$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_PIN="$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_DEST="$SANDBOX/plugins"
  export IINA_PLUGINS_STATE="$SANDBOX/plugin-state"
  run "$REPO_ROOT/checks/iina-plugins.sh" install --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsafe archive extra field"* ]]
  [ ! -e "$SANDBOX/plugins/io.iina.ytdl.iinaplugin" ]
}

@test "completed shader backup refuses tampered content before restore" {
  make_shader_fixture
  local dest="$SANDBOX/iina-mpv" state="$SANDBOX/shader-state" backup
  mkdir -p "$dest/shaders"
  printf 'old shader\n' >"$dest/shaders/old.glsl"
  export IINA_SHADERS_PIN="$SANDBOX/shaders-pin.json"
  export IINA_SHADERS_DEST_ROOT="$dest"
  export IINA_SHADERS_STATE="$state"
  run "$REPO_ROOT/checks/iina-shaders.sh" install --apply
  [ "$status" -eq 0 ]
  backup="$(find "$state" -mindepth 1 -maxdepth 1 -type d ! -name 'download.*' -print -quit)"
  printf 'changed\n' >>"$backup/shaders/old.glsl"
  run "$REPO_ROOT/checks/iina-shaders.sh" restore --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"snapshot content mismatch"* ]]
  [ -f "$dest/shaders/Anime4K_Test.glsl" ]
}

@test "completed plugin backup refuses tampered content before restore" {
  make_plugin_fixture
  local dest="$SANDBOX/plugins" state="$SANDBOX/plugin-state" backup
  mkdir -p "$dest/io.iina.ytdl.iinaplugin"
  printf 'old\n' >"$dest/io.iina.ytdl.iinaplugin/old.txt"
  export IINA_PLUGINS_PIN="$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_DEST="$dest"
  export IINA_PLUGINS_STATE="$state"
  run "$REPO_ROOT/checks/iina-plugins.sh" install --apply
  [ "$status" -eq 0 ]
  backup="$(find "$state" -mindepth 1 -maxdepth 1 -type d ! -name 'download.*' -print -quit)"
  printf 'changed\n' >>"$backup/io.iina.ytdl.iinaplugin/old.txt"
  run "$REPO_ROOT/checks/iina-plugins.sh" restore --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"snapshot content mismatch"* ]]
  [ -f "$dest/io.iina.ytdl.iinaplugin/Info.json" ]
}

@test "official plugin pin rejects repository reassignment" {
  make_plugin_fixture
  /usr/bin/perl -0pi -e 's|iina/plugin-online-media|iina/plugin-other|' "$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_PIN="$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_DEST="$SANDBOX/plugins"
  run "$REPO_ROOT/checks/iina-plugins.sh" preview
  [ "$status" -ne 0 ]
  [[ "$output" == *"repo must match its official repository"* ]]
}

@test "official plugin pin rejects destination reassignment" {
  make_plugin_fixture
  /usr/bin/perl -0pi -e 's/io\.iina\.ytdl\.iinaplugin/other-installed.iinaplugin/' "$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_PIN="$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_DEST="$SANDBOX/plugins"
  run "$REPO_ROOT/checks/iina-plugins.sh" preview
  [ "$status" -ne 0 ]
  [[ "$output" == *"exact pinned bundle name"* ]]
  [ ! -e "$SANDBOX/plugins/other-installed.iinaplugin" ]
}

@test "official plugin install recovers all three targets after a staged move fails" {
  make_plugin_fixture
  local dest="$SANDBOX/plugins" state="$SANDBOX/plugin-state" id dir
  mkdir -p "$dest/.preferences" "$dest/other.iinaplugin"
  printf 'private prefs\n' >"$dest/.preferences/sentinel"
  printf 'unrelated\n' >"$dest/other.iinaplugin/sentinel"
  for id in io.iina.ytdl io.iina.opensub io.iina.user-script; do
    dir="$dest/$id.iinaplugin"
    mkdir -p "$dir"
    printf '{"identifier":"%s","version":"old"}\n' "$id" >"$dir/Info.json"
  done
  cat >"$FAKE_BIN/mv" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"stage/io.iina.opensub.iinaplugin"* ]]; then exit 91; fi
exec /bin/mv "$@"
SH
  chmod +x "$FAKE_BIN/mv"
  export IINA_PLUGINS_PIN="$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_DEST="$dest"
  export IINA_PLUGINS_STATE="$state"
  run "$REPO_ROOT/checks/iina-plugins.sh" install --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"interrupted install recovered"* ]]
  for id in io.iina.ytdl io.iina.opensub io.iina.user-script; do
    [ -f "$dest/$id.iinaplugin/Info.json" ]
    [[ "$(UV_NO_PROJECT=1 uv run --offline --no-project python -I -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$dest/$id.iinaplugin/Info.json")" == old ]]
  done
  [ -f "$dest/other.iinaplugin/sentinel" ]
  [ -f "$dest/.preferences/sentinel" ]
}

@test "permission-list plugin metadata uses package version for doctor" {
  local dest="$SANDBOX/plugins"
  local id version folder
  mkdir -p "$dest"
  make_plugin_fixture
  for id in io.iina.ytdl io.iina.opensub io.iina.user-script; do
    case "$id" in
      io.iina.ytdl) version=0.9.10 ;;
      io.iina.opensub) version=0.9.6 ;;
      io.iina.user-script) version=0.9.3 ;;
    esac
    folder="$dest/$id.iinaplugin"
    mkdir -p "$folder"
    printf '["show-osd"]\n' >"$folder/Info.json"
    case "$id" in
      io.iina.ytdl) package_name=iina-plugin-ytdl ;;
      io.iina.opensub) package_name=iina-plugin-opensub ;;
      io.iina.user-script) package_name=iina-plugin-user-scripts ;;
    esac
    printf '{"name":"%s","version":"%s"}\n' "$package_name" "$version" >"$folder/package.json"
  done
  export IINA_PLUGINS_PIN="$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_DEST="$dest"
  run "$REPO_ROOT/checks/iina-plugins.sh" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"all official plugins match pin"* ]]
}

@test "official plugin restore removes only an exact target that was originally absent" {
  command -v zip >/dev/null || skip "zip unavailable"
  make_plugin_fixture
  local dest="$SANDBOX/plugins"
  local state="$SANDBOX/plugin-state"
  mkdir -p "$dest/other.iinaplugin" "$dest/.preferences"
  printf '%s\n' 'independent plugin' >"$dest/other.iinaplugin/sentinel"
  printf '%s\n' 'private prefs' >"$dest/.preferences/sentinel"
  export IINA_PLUGINS_PIN="$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_DEST="$dest"
  export IINA_PLUGINS_STATE="$state"
  run "$REPO_ROOT/checks/iina-plugins.sh" install --apply
  [ "$status" -eq 0 ]
  [ -d "$dest/io.iina.ytdl.iinaplugin" ]
  run "$REPO_ROOT/checks/iina-plugins.sh" restore --apply
  [ "$status" -eq 0 ]
  [ ! -e "$dest/io.iina.ytdl.iinaplugin" ]
  [ -f "$dest/other.iinaplugin/sentinel" ]
  [ -f "$dest/.preferences/sentinel" ]
}

@test "official plugin restore failure recovers prior target set and preferences" {
  make_plugin_fixture
  local dest="$SANDBOX/plugins" state="$SANDBOX/plugin-state" id dir backup
  mkdir -p "$dest/.preferences" "$dest/other.iinaplugin"
  printf 'private prefs\n' >"$dest/.preferences/sentinel"
  printf 'unrelated\n' >"$dest/other.iinaplugin/sentinel"
  for id in io.iina.ytdl io.iina.opensub io.iina.user-script; do
    dir="$dest/$id.iinaplugin"
    mkdir -p "$dir"
    printf '{"identifier":"%s","version":"old"}\n' "$id" >"$dir/Info.json"
  done
  export IINA_PLUGINS_PIN="$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_DEST="$dest"
  export IINA_PLUGINS_STATE="$state"
  run "$REPO_ROOT/checks/iina-plugins.sh" install --apply
  [ "$status" -eq 0 ]
  cat >"$FAKE_BIN/mv" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"staged/io.iina.opensub.iinaplugin"* ]]; then exit 91; fi
exec /bin/mv "$@"
SH
  chmod +x "$FAKE_BIN/mv"
  run "$REPO_ROOT/checks/iina-plugins.sh" restore --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"interrupted restore recovered"* ]]
  for id in io.iina.ytdl io.iina.opensub io.iina.user-script; do
    [[ "$(UV_NO_PROJECT=1 uv run --offline --no-project python -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$dest/$id.iinaplugin/Info.json")" == 0.9.* ]]
  done
  [ -f "$dest/.preferences/sentinel" ]
  [ -f "$dest/other.iinaplugin/sentinel" ]
}

@test "official plugin installer applies, preserves runtime prefs, and restores old versions" {
  command -v zip >/dev/null || skip "zip unavailable"
  make_plugin_fixture
  local dest="$SANDBOX/plugins"
  local state="$SANDBOX/plugin-state"
  local id dir
  mkdir -p "$dest/.preferences"
  printf '%s\n' 'runtime prefs' >"$dest/.preferences/sentinel"
  for id in io.iina.ytdl io.iina.opensub io.iina.user-script; do
    dir="$dest/$id.iinaplugin"
    mkdir -p "$dir"
    printf '{"identifier":"%s","version":"old"}\n' "$id" >"$dir/Info.json"
  done

  export IINA_PLUGINS_PIN="$SANDBOX/plugins-pin.json"
  export IINA_PLUGINS_DEST="$dest"
  export IINA_PLUGINS_STATE="$state"

  run "$REPO_ROOT/checks/iina-plugins.sh" install --apply
  [ "$status" -eq 0 ]
  [[ "$(UV_NO_PROJECT=1 uv run --offline --no-project python -I -c "import json; print(json.load(open('$dest/io.iina.ytdl.iinaplugin/Info.json'))['version'])")" == "0.9.10" ]]
  [[ "$(cat "$dest/.preferences/sentinel")" == "runtime prefs" ]]

  run "$REPO_ROOT/checks/iina-plugins.sh" doctor
  [ "$status" -eq 0 ]
  printf '{"identifier":"io.iina.ytdl","version":"drift"}\n' >"$dest/io.iina.ytdl.iinaplugin/Info.json"
  run "$REPO_ROOT/checks/iina-plugins.sh" doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"drift io.iina.ytdl"* ]]

  run "$REPO_ROOT/checks/iina-plugins.sh" restore --apply
  [ "$status" -eq 0 ]
  [[ "$(UV_NO_PROJECT=1 uv run --offline --no-project python -I -c "import json; print(json.load(open('$dest/io.iina.ytdl.iinaplugin/Info.json'))['version'])")" == "old" ]]
  [[ "$(cat "$dest/.preferences/sentinel")" == "runtime prefs" ]]
}
