#!/usr/bin/env bats
# Native IINA source and exact-target migration tests; destinations are disposable.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/iina-native-bats.XXXXXX")"
  export IINA_NATIVE_SOURCE="$REPO_ROOT/rig/home"
  export IINA_NATIVE_SUPPORT="$SANDBOX/support"
  export IINA_NATIVE_HAMMERSPOON="$SANDBOX/hammerspoon"
  export IINA_NATIVE_MPV="$SANDBOX/mpv"
  export IINA_NATIVE_STATE="$SANDBOX/state"
  export IINA_OPERATION_LOCK="$SANDBOX/iina-operation.lock"
  export IINA_NATIVE_DOMAIN="iina-native-test-$$"
  mkdir -p "$SANDBOX/bin" "$IINA_NATIVE_SUPPORT/input_conf" "$IINA_NATIVE_SUPPORT/plugins/.data" \
    "$IINA_NATIVE_SUPPORT/plugins/.preferences" "$IINA_NATIVE_HAMMERSPOON/iina_qol" "$IINA_NATIVE_MPV/shaders"
  export PATH="$SANDBOX/bin:$PATH"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$SANDBOX/bin/pgrep"
  # The fake defaults program keeps the tests from touching macOS preferences.
  printf '#!/usr/bin/env bash\nset -euo pipefail\nbase="%s"\nkey="$3"\nfile="$base/defaults-$key"\ncase "$1" in\n  read) [[ -f "$file" ]] && /bin/cat "$file" ;;\n  write) printf "%%s\\n" "$5" >"$file" ;;\n  delete) /bin/rm -f "$file" ;;\nesac\n' "$SANDBOX" >"$SANDBOX/bin/defaults"
  chmod +x "$SANDBOX/bin/pgrep" "$SANDBOX/bin/defaults"
  printf 'IINA-QoL\n' >"$SANDBOX/defaults-currentInputConfigName"
  printf '3\n' >"$SANDBOX/defaults-horizontalScrollAction"
  printf '3\n' >"$SANDBOX/defaults-verticalScrollAction"
  printf '1\n' >"$SANDBOX/defaults-useUserDefinedConfDir"
  printf '0\n' >"$SANDBOX/defaults-middleClickAction"
  printf '%s\n' "$IINA_NATIVE_MPV" >"$SANDBOX/defaults-userDefinedConfDir"
  printf 'old profile\n' >"$IINA_NATIVE_SUPPORT/input_conf/IINA-QoL.conf"
  mkdir -p "$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/lib"
  local file
  for file in main.js lib/zoom.js lib/settings.js help.html preferences.html; do
    printf 'fixture:%s\n' "$file" >"$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/$file"
  done
  export IINA_TEST_PLUGIN_ROOT="$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin"
  cat >"$SANDBOX/bin/shasum" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == -a && "${2:-}" == 256 && "${3:-}" == "$IINA_TEST_PLUGIN_ROOT/"* ]]; then
  name="${3#"$IINA_TEST_PLUGIN_ROOT/"}"
  if [[ "$(/bin/cat "$3")" == "fixture:$name" ]]; then
    case "$name" in
      main.js) digest=a78aca30fe34f0daa395e518539f244d8957866bc56478c4a2ae2598dc337368 ;;
      lib/zoom.js) digest=5831a0d5f42c4618751b152dcfc23ac7a63966f158f0669330870d9c037f173b ;;
      lib/settings.js) digest=09903ff3609468166f2a5cb3c08ca16653494401a85096016c74d289eb14d68b ;;
      help.html) digest=c5a7adf67a25e6d44f85c2e0a29b56654e0ff706523e2d7e9a5b8a1d3c9c8488 ;;
      preferences.html) digest=20c326337d0c71b2730e1ab9a0545f06b67aeb03fa41c95bc8c473e5c9e3c84e ;;
      *) digest= ;;
    esac
    if [[ -n "$digest" ]]; then printf '%s  %s\n' "$digest" "$3"; exit 0; fi
  fi
fi
exec /usr/bin/shasum "$@"
SH
  chmod +x "$SANDBOX/bin/shasum"
  mkdir -p "$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/.data" \
    "$IINA_NATIVE_SUPPORT/plugins/other.iinaplugin"
  printf '["show-osd"]' >"$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/Info.json"
  printf 'private old state\n' >"$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/.data/sentinel"
  printf 'other plugin\n' >"$IINA_NATIVE_SUPPORT/plugins/other.iinaplugin/sentinel"
  printf 'global data\n' >"$IINA_NATIVE_SUPPORT/plugins/.data/sentinel"
  printf 'global preferences\n' >"$IINA_NATIVE_SUPPORT/plugins/.preferences/sentinel"
  printf 'downloaded shader\n' >"$IINA_NATIVE_MPV/shaders/sentinel"
  printf 'old bridge\n' >"$IINA_NATIVE_HAMMERSPOON/iina_qol.lua"
  printf 'old gesture\n' >"$IINA_NATIVE_HAMMERSPOON/iina_qol/gesture.lua"
  printf 'old window\n' >"$IINA_NATIVE_HAMMERSPOON/iina_qol/window.lua"
  printf 'before\n-- >>> IINA QOL >>>\nrequire("iina_qol")\n-- <<< IINA QOL <<<\nafter\n' \
    >"$IINA_NATIVE_HAMMERSPOON/init.lua"
}

teardown() {
  /bin/rm -rf -- "$SANDBOX"
}

snapshot() {
  (cd "$SANDBOX" && find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do cksum "$file"; done)
}

reviewed_backup() {
  "$REPO_ROOT/checks/iina-native.sh" snapshot --apply >/dev/null || return 1
  find "$IINA_NATIVE_STATE" -mindepth 1 -maxdepth 1 -type d -print -quit
}

apply_reviewed() {
  local backup
  backup="$(reviewed_backup)" || return 1
  "$REPO_ROOT/checks/iina-native.sh" apply --backup "$backup" --apply
}

@test "actual native source passes the static contract" {
  run "$REPO_ROOT/checks/iina-config.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"iina-config: ok"* ]]
}

@test "native preview and doctor never mutate or create backup state" {
  before="$(snapshot)"
  run "$REPO_ROOT/checks/iina-native.sh" preview
  [ "$status" -eq 0 ]
  [[ "$output" == *"preserve all sibling plugins"* ]]
  run "$REPO_ROOT/checks/iina-native.sh" doctor
  [ "$status" -eq 0 ]
  run "$REPO_ROOT/checks/iina-native.sh" apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  [ "$(snapshot)" = "$before" ]
  [ ! -e "$IINA_NATIVE_STATE" ]
}

@test "sandbox apply retires only named QoL paths and explicit restore recovers them" {
  run apply_reviewed
  [ "$status" -eq 0 ]
  [[ "$output" == *"iina-native: migrated"* ]]
  [ -f "$IINA_NATIVE_SUPPORT/input_conf/IINA-Native.conf" ]
  [ ! -e "$IINA_NATIVE_SUPPORT/input_conf/IINA-QoL.conf" ]
  [ ! -e "$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin" ]
  [ ! -e "$IINA_NATIVE_HAMMERSPOON/iina_qol.lua" ]
  [ "$(<"$IINA_NATIVE_HAMMERSPOON/init.lua")" = $'before\nafter' ]
  [ -f "$IINA_NATIVE_SUPPORT/plugins/other.iinaplugin/sentinel" ]
  [ -f "$IINA_NATIVE_SUPPORT/plugins/.data/sentinel" ]
  [ -f "$IINA_NATIVE_SUPPORT/plugins/.preferences/sentinel" ]
  [ -f "$IINA_NATIVE_MPV/shaders/sentinel" ]
  [ "$(<"$SANDBOX/defaults-currentInputConfigName")" = IINA-Native ]
  backup="$(find "$IINA_NATIVE_STATE" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  [ -f "$backup/plugin/.data/sentinel" ]
  run "$REPO_ROOT/checks/iina-native.sh" restore --backup "$backup"
  [ "$status" -eq 0 ]
  [ ! -e "$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin" ]
  run "$REPO_ROOT/checks/iina-native.sh" restore --backup "$backup" --apply
  [ "$status" -eq 0 ]
  [ ! -e "$IINA_NATIVE_SUPPORT/input_conf/IINA-Native.conf" ]
  [ -f "$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/.data/sentinel" ]
  [ -f "$IINA_NATIVE_SUPPORT/plugins/other.iinaplugin/sentinel" ]
  [ -f "$IINA_NATIVE_SUPPORT/plugins/.data/sentinel" ]
  [ "$(<"$SANDBOX/defaults-currentInputConfigName")" = IINA-QoL ]
  grep -Fq -- 'require("iina_qol")' "$IINA_NATIVE_HAMMERSPOON/init.lua"
}

@test "exclusive lock and prior dirty marker block mutation" {
  mkdir -p "$IINA_NATIVE_STATE"
  exec 7>"$IINA_OPERATION_LOCK"
  flock -n 7
  run "$REPO_ROOT/checks/iina-native.sh" snapshot --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"another IINA operation is running"* ]]
  [ ! -e "$IINA_NATIVE_STATE/.dirty" ]
  flock -u 7
  exec 7>&-
  exec 7>"$IINA_NATIVE_STATE/.lock"
  flock -n 7
  run "$REPO_ROOT/checks/iina-native.sh" snapshot --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"another IINA migration/snapshot/restore is running"* ]]
  flock -u 7
  exec 7>&-
  printf 'interrupted operation\n' >"$IINA_NATIVE_STATE/.dirty"
  run "$REPO_ROOT/checks/iina-native.sh" snapshot --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"prior IINA operation left dirty state"* ]]
  [ -f "$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/Info.json" ]
  /bin/rm -f "$IINA_NATIVE_STATE/.dirty"
  mkdir -p "$IINA_NATIVE_STATE/20260929T000000Z.test"
  printf 'apply-in-progress\n' >"$IINA_NATIVE_STATE/20260929T000000Z.test/dirty"
  run "$REPO_ROOT/checks/iina-native.sh" snapshot --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"dirty IINA snapshot requires inspection"* ]]
}

@test "reviewed snapshot is required and stale live targets are rejected before mutation" {
  before="$(snapshot)"
  run "$REPO_ROOT/checks/iina-native.sh" apply --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires --backup PATH"* ]]
  [ "$(snapshot)" = "$before" ]
  [ ! -e "$IINA_NATIVE_STATE" ]
  local backup
  backup="$(reviewed_backup)"
  [ -f "$backup/complete" ]
  [ -f "$backup/sources.sha256" ]
  before="$(snapshot)"
  printf 'changed before approval\n' >>"$IINA_NATIVE_SUPPORT/input_conf/IINA-QoL.conf"
  run "$REPO_ROOT/checks/iina-native.sh" apply --backup "$backup" --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"live target changed since reviewed snapshot"* ]]
  [ -f "$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/Info.json" ]
  [ ! -e "$IINA_NATIVE_SUPPORT/input_conf/IINA-Native.conf" ]
  [ ! -e "$backup/dirty" ]
}

@test "reviewed snapshot rejects changed native source before touching live state" {
  local source="$SANDBOX/source" backup
  mkdir -p "$source/Library/Application Support/com.colliderli.iina/input_conf" "$source/private_dot_config/iina-mpv"
  cp "$IINA_NATIVE_SOURCE/Library/Application Support/com.colliderli.iina/input_conf/IINA-Native.conf" \
    "$source/Library/Application Support/com.colliderli.iina/input_conf/IINA-Native.conf"
  cp "$IINA_NATIVE_SOURCE/private_dot_config/iina-mpv/"{mpv.conf,shaders-pin.json} "$source/private_dot_config/iina-mpv/"
  export IINA_NATIVE_SOURCE="$source"
  backup="$(reviewed_backup)"
  printf '# changed after review\n' >>"$source/private_dot_config/iina-mpv/mpv.conf"
  run "$REPO_ROOT/checks/iina-native.sh" apply --backup "$backup" --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"source changed since reviewed snapshot"* ]]
  [ -f "$IINA_NATIVE_SUPPORT/input_conf/IINA-QoL.conf" ]
  [ -f "$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/Info.json" ]
  [ ! -e "$IINA_NATIVE_SUPPORT/input_conf/IINA-Native.conf" ]
  [ ! -e "$backup/dirty" ]
}

@test "incomplete migration snapshot refuses restore before mutation" {
  local backup="$IINA_NATIVE_STATE/20260928T000000Z.incomplete"
  mkdir -p "$backup"
  printf 'iina-native-v2\n' >"$backup/version"
  before="$(snapshot)"
  run "$REPO_ROOT/checks/iina-native.sh" restore --backup "$backup" --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing backup status"* ]]
  [ "$(snapshot)" = "$before" ]
}

@test "backup copy failure leaves live targets intact and snapshot incomplete" {
  local fake="$SANDBOX/bin/cp"
  cat >"$fake" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"IINA-QoL.iinaplugin"* ]]; then exit 91; fi
exec /bin/cp "$@"
SH
  chmod +x "$fake"
  run "$REPO_ROOT/checks/iina-native.sh" snapshot --apply
  [ "$status" -ne 0 ]
  [ -f "$IINA_NATIVE_SUPPORT/input_conf/IINA-QoL.conf" ]
  [ -f "$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/Info.json" ]
  [ ! -e "$IINA_NATIVE_SUPPORT/input_conf/IINA-Native.conf" ]
  [ -f "$IINA_NATIVE_SUPPORT/plugins/other.iinaplugin/sentinel" ]
  [ "$(<"$SANDBOX/defaults-currentInputConfigName")" = IINA-QoL ]
  local backup
  backup="$(find "$IINA_NATIVE_STATE" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  [ -n "$backup" ]
  [ ! -e "$backup/complete" ]
  [ ! -e "$backup/dirty" ]
}

@test "TERM during migration restores the named sandbox targets" {
  local fake="$SANDBOX/bin/mv"
  cat >"$fake" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"shaders-pin.json"* ]]; then kill -TERM "$PPID"; fi
exec /bin/mv "$@"
SH
  chmod +x "$fake"
  local backup
  backup="$(reviewed_backup)"
  run "$REPO_ROOT/checks/iina-native.sh" apply --backup "$backup" --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"recovered from"* ]]
  [ -f "$IINA_NATIVE_SUPPORT/input_conf/IINA-QoL.conf" ]
  [ -f "$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/Info.json" ]
  [ ! -e "$IINA_NATIVE_SUPPORT/input_conf/IINA-Native.conf" ]
  [ -f "$IINA_NATIVE_SUPPORT/plugins/other.iinaplugin/sentinel" ]
  [ "$(<"$SANDBOX/defaults-currentInputConfigName")" = IINA-QoL ]
}

@test "migration error after staging restores the named sandbox targets" {
  local fake="$SANDBOX/bin/mv"
  printf '#!/usr/bin/env bash\nif [[ "$*" == *"shaders-pin.json" ]]; then exit 91; fi\nexec /bin/mv "$@"\n' >"$fake"
  chmod +x "$fake"
  before="$(snapshot)"
  local backup
  backup="$(reviewed_backup)"
  run "$REPO_ROOT/checks/iina-native.sh" apply --backup "$backup" --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"recovered from"* ]]
  [ -f "$IINA_NATIVE_SUPPORT/input_conf/IINA-QoL.conf" ]
  [ -f "$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/Info.json" ]
  [ ! -e "$IINA_NATIVE_SUPPORT/input_conf/IINA-Native.conf" ]
  [ -f "$IINA_NATIVE_SUPPORT/plugins/other.iinaplugin/sentinel" ]
  [ -f "$IINA_NATIVE_SUPPORT/plugins/.preferences/sentinel" ]
  [ "$(<"$SANDBOX/defaults-currentInputConfigName")" = IINA-QoL ]
  /bin/rm -f "$fake"
  [ "$(snapshot)" != "$before" ] # only the recoverable snapshot is new
}

@test "repeated migration is a no-op after the first sandbox apply" {
  run apply_reviewed
  [ "$status" -eq 0 ]
  before="$(snapshot)"
  backup_count="$(find "$IINA_NATIVE_STATE" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  run "$REPO_ROOT/checks/iina-native.sh" apply --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"already migrated; no changes"* ]]
  [ "$(snapshot)" = "$before" ]
  [ "$(find "$IINA_NATIVE_STATE" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" = "$backup_count" ]
}

@test "migration refuses an ambiguous QoL plugin identity before backup" {
  printf '["show-osd"]\n' >"$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/Info.json"
  before="$(snapshot)"
  run "$REPO_ROOT/checks/iina-native.sh" apply --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"QoL plugin identity unavailable"* ]]
  [ "$(snapshot)" = "$before" ]
  [ ! -e "$IINA_NATIVE_STATE" ]
}

@test "permission-list identity requires every historical public code and UI fingerprint" {
  printf '["show-osd"]' >"$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/Info.json"
  run "$REPO_ROOT/checks/iina-native.sh" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"ready QoL plugin identity confirmed"* ]]
  printf '{"identifier":"com.wyattowalsh.iina-qol","version":"4.1.0"}\n' >"$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/Info.json"
  run "$REPO_ROOT/checks/iina-native.sh" doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocked QoL plugin identity unavailable"* ]]
  printf '["show-osd"]\n' >"$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/Info.json"
  printf 'tampered\n' >>"$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/lib/zoom.js"
  run "$REPO_ROOT/checks/iina-native.sh" doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocked QoL plugin identity unavailable"* ]]
  [ ! -e "$IINA_NATIVE_STATE" ]
}

@test "tampered complete migration snapshot refuses restore before mutation" {
  run apply_reviewed
  [ "$status" -eq 0 ]
  local backup
  backup="$(find "$IINA_NATIVE_STATE" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  printf 'tampered\n' >>"$backup/plugin/Info.json"
  local before
  before="$(snapshot)"
  run "$REPO_ROOT/checks/iina-native.sh" restore --backup "$backup" --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"snapshot content mismatch: plugin"* ]]
  [ "$(snapshot)" = "$before" ]
}

@test "TERM during restore recovers the pre-restore state" {
  run apply_reviewed
  [ "$status" -eq 0 ]
  local original fake
  original="$(find "$IINA_NATIVE_STATE" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  fake="$SANDBOX/bin/cp"
  cat >"$fake" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"/old_profile "* ]]; then kill -TERM "$PPID"; fi
exec /bin/cp "$@"
SH
  chmod +x "$fake"
  run "$REPO_ROOT/checks/iina-native.sh" restore --backup "$original" --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"interrupted restore recovered from pre-restore rescue"* ]]
  [ -f "$IINA_NATIVE_SUPPORT/input_conf/IINA-Native.conf" ]
  [ ! -e "$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin" ]
  [ "$(<"$SANDBOX/defaults-currentInputConfigName")" = IINA-Native ]
}

@test "failed restore recovers exact pre-restore state from a rescue snapshot" {
  run apply_reviewed
  [ "$status" -eq 0 ]
  local original fake rescue
  original="$(find "$IINA_NATIVE_STATE" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  printf 'post migration private change\n' >"$IINA_NATIVE_SUPPORT/plugins/.preferences/after"
  local before
  before="$(snapshot)"
  fake="$SANDBOX/bin/cp"
  cat >"$fake" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"/old_profile "* ]]; then exit 91; fi
exec /bin/cp "$@"
SH
  chmod +x "$fake"
  run "$REPO_ROOT/checks/iina-native.sh" restore --backup "$original" --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"interrupted restore recovered from pre-restore rescue"* ]]
  /bin/rm -f "$fake"
  [ -f "$IINA_NATIVE_SUPPORT/input_conf/IINA-Native.conf" ]
  [ ! -e "$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin" ]
  [ -f "$IINA_NATIVE_SUPPORT/plugins/.preferences/after" ]
  [ "$(<"$SANDBOX/defaults-currentInputConfigName")" = IINA-Native ]
  rescue="$(find "$IINA_NATIVE_STATE" -mindepth 1 -maxdepth 1 -type d ! -path "$original" -print -quit)"
  [ -f "$rescue/complete" ]
  [ ! -e "$rescue/restore-dirty" ]
  [ "$(snapshot)" != "$before" ] # only the rescue snapshot is new
}

@test "dirty migration snapshot refuses independent restore before mutation" {
  run apply_reviewed
  [ "$status" -eq 0 ]
  local backup
  backup="$(find "$IINA_NATIVE_STATE" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  printf 'apply-in-progress\n' >"$backup/dirty"
  local before
  before="$(snapshot)"
  run "$REPO_ROOT/checks/iina-native.sh" restore --backup "$backup" --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"dirty marker"* ]]
  [ "$(snapshot)" = "$before" ]
}

@test "doctor reports every preference and blocks ambiguous identity without mutation" {
  printf '["show-osd"]\n' >"$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin/Info.json"
  printf '4\n' >"$SANDBOX/defaults-verticalScrollAction"
  before="$(snapshot)"
  run "$REPO_ROOT/checks/iina-native.sh" doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocked QoL plugin identity unavailable"* ]]
  [[ "$output" == *"ready preference horizontalScrollAction"* ]]
  [[ "$output" == *"blocked preference verticalScrollAction"* ]]
  [[ "$output" == *"ready preference useUserDefinedConfDir"* ]]
  [[ "$output" == *"ready preference userDefinedConfDir"* ]]
  [[ "$output" == *"ready preference middleClickAction"* ]]
  [ "$(snapshot)" = "$before" ]
  [ ! -e "$IINA_NATIVE_STATE" ]
}

@test "migration refuses incompatible native scroll settings before backup" {
  printf '1\n' >"$SANDBOX/defaults-horizontalScrollAction"
  before="$(snapshot)"
  run "$REPO_ROOT/checks/iina-native.sh" apply --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"horizontalScrollAction must already be 3"* ]]
  [ "$(snapshot)" = "$before" ]
  [ ! -e "$IINA_NATIVE_STATE" ]
}

@test "unmarked Hammerspoon loader is refused without changing destination" {
  printf 'require("iina_qol")\n' >"$IINA_NATIVE_HAMMERSPOON/init.lua"
  before="$(snapshot)"
  run "$REPO_ROOT/checks/iina-native.sh" apply --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"unmarked IINA loader"* ]]
  [ "$(snapshot)" = "$before" ]
  [ ! -e "$IINA_NATIVE_STATE" ]
}

@test "a symlinked plugin destination is refused before any mutation" {
  /bin/rm -rf -- "$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin"
  ln -s "$SANDBOX" "$IINA_NATIVE_SUPPORT/plugins/IINA-QoL.iinaplugin"
  before="$(snapshot)"
  run "$REPO_ROOT/checks/iina-native.sh" apply --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"symlink target refused"* ]]
  [ "$(snapshot)" = "$before" ]
  [ ! -e "$IINA_NATIVE_STATE" ]
}

@test "native source rejects a private bridge binding" {
  local source="$SANDBOX/source"
  mkdir -p "$source/Library/Application Support/com.colliderli.iina/input_conf" "$source/private_dot_config/iina-mpv"
  cp "$IINA_NATIVE_SOURCE/Library/Application Support/com.colliderli.iina/input_conf/IINA-Native.conf" \
    "$source/Library/Application Support/com.colliderli.iina/input_conf/IINA-Native.conf"
  cp "$IINA_NATIVE_SOURCE/private_dot_config/iina-mpv/"{mpv.conf,shaders-pin.json} "$source/private_dot_config/iina-mpv/"
  cp "$IINA_NATIVE_SOURCE/Library/Application Support/com.colliderli.iina/official-plugins-pin.json" \
    "$source/Library/Application Support/com.colliderli.iina/official-plugins-pin.json"
  printf 'F17 ignore\n' >>"$source/Library/Application Support/com.colliderli.iina/input_conf/IINA-Native.conf"
  export IINA_NATIVE_SOURCE="$source"
  run "$REPO_ROOT/checks/iina-config.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"custom QoL/bridge dependency"* ]]
}
