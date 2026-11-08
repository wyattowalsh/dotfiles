#!/usr/bin/env bash
# Exact-target native IINA migration. No live changes without --apply.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${IINA_NATIVE_SOURCE:-$ROOT/rig/home}"
SUPPORT="${IINA_NATIVE_SUPPORT:-$HOME/Library/Application Support/com.colliderli.iina}"
HAMMERSPOON="${IINA_NATIVE_HAMMERSPOON:-$HOME/.hammerspoon}"
MPV="${IINA_NATIVE_MPV:-$HOME/.config/iina-mpv}"
STATE="${IINA_NATIVE_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/iina-native}"
DOMAIN="${IINA_NATIVE_DOMAIN:-com.colliderli.iina}"
PROFILE="$SOURCE/Library/Application Support/com.colliderli.iina/input_conf/IINA-Native.conf"
MPV_SOURCE="$SOURCE/private_dot_config/iina-mpv"
PLUGIN="$SUPPORT/plugins/IINA-QoL.iinaplugin"
OLD_PROFILE="$SUPPORT/input_conf/IINA-QoL.conf"
NEW_PROFILE="$SUPPORT/input_conf/IINA-Native.conf"
INIT="$HAMMERSPOON/init.lua"
BEGIN_MARKER='-- >>> IINA QOL >>>'
END_MARKER='-- <<< IINA QOL <<<'
LEGACY_BEGIN='-- >>> IINA QOL SCROLL ZOOM >>>'
LEGACY_END='-- <<< IINA QOL SCROLL ZOOM <<<'
CMD="${1:-preview}"
APPLY=0
BACKUP=""
RESTORE_ORIGINAL=""
RESTORE_RESCUE=""
if [[ $# -gt 0 ]]; then shift; fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --dry-run)
      APPLY=0
      shift
      ;;
    --backup)
      [[ $# -ge 2 ]] || {
        printf 'iina-native: --backup requires a path\n' >&2
        exit 1
      }
      BACKUP="$2"
      shift 2
      ;;
    *)
      printf 'iina-native: unknown option %s\n' "$1" >&2
      exit 1
      ;;
  esac
done
case "$CMD" in preview | doctor | snapshot | apply | restore) ;; *)
  printf 'iina-native: unknown command %s\n' "$CMD" >&2
  exit 1
  ;;
esac

die() {
  printf 'iina-native: %s\n' "$*" >&2
  exit 1
}
acquire_mutation_lock() {
  command -v flock >/dev/null 2>&1 || die 'flock unavailable; refusing mutation without exclusive lock'
  check_parents "$STATE"
  directory_or_absent "$STATE"
  mkdir -p "$STATE"
  [[ -O "$STATE" ]] || die "state directory must belong to the current user: $STATE"
  local operation_lock="${IINA_OPERATION_LOCK:-$(dirname "$STATE")/.iina-operation.lock}"
  check_parents "$operation_lock"
  [[ ! -L "$operation_lock" ]] || die 'symlinked operation lock refused'
  exec 9>"$operation_lock"
  flock -n 9 || die 'another IINA operation is running'
  [[ ! -L "$STATE/.lock" ]] || die 'symlinked lock refused'
  exec 8>"$STATE/.lock"
  flock -n 8 || die 'another IINA migration/snapshot/restore is running'
  if [[ -e "$STATE/.dirty" || -L "$STATE/.dirty" ]]; then
    die "prior IINA operation left dirty state at $STATE/.dirty; inspect before retrying"
  fi
  local candidate
  for candidate in "$STATE"/*; do
    [[ -d "$candidate" && ! -L "$candidate" ]] || continue
    if [[ -e "$candidate/dirty" || -L "$candidate/dirty" || -e "$candidate/restore-dirty" || -L "$candidate/restore-dirty" ]]; then
      die "dirty IINA snapshot requires inspection before mutation: $candidate"
    fi
  done
}
mark_mutation_started() {
  printf '%s\n' "$1" >"$STATE/.dirty"
}
clear_mutation_marker() {
  /bin/rm -f -- "$STATE/.dirty"
}
require_iina_quit() {
  command -v pgrep >/dev/null 2>&1 || die 'pgrep unavailable; cannot verify IINA quit'
  if pgrep -x IINA >/dev/null 2>&1; then die 'quit IINA before mutation'; fi
}
regular_or_absent() {
  local path="$1"
  [[ ! -L "$path" ]] || die "symlink target refused: $path"
  [[ ! -e "$path" || -f "$path" ]] || die "non-file target refused: $path"
}
directory_or_absent() {
  local path="$1"
  [[ ! -L "$path" ]] || die "symlink target refused: $path"
  [[ ! -e "$path" || -d "$path" ]] || die "non-directory target refused: $path"
}
check_parents() {
  local path="$1" parent
  parent="$(dirname "$path")"
  while [[ "$parent" != / && "$parent" != . ]]; do
    if [[ -L "$parent" ]]; then
      case "$parent" in
        /var | /tmp | /private/var | /private/tmp) ;; # macOS system aliases used by mktemp
        *) die "symlink parent refused: $parent" ;;
      esac
    fi
    parent="$(dirname "$parent")"
  done
}
check_tree() {
  local root="$1"
  [[ ! -d "$root" ]] && return 0
  if find "$root" -type l -print -quit | grep -q .; then
    die "symlink inside plugin tree refused: $root"
  fi
}
check_markers() {
  [[ -f "$INIT" ]] || return 0
  local result
  result="$(awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" -v lb="$LEGACY_BEGIN" -v le="$LEGACY_END" '
    $0 == b || $0 == lb { if (open || seen) bad=1; open=($0 == b ? "current" : "legacy"); seen=1; next }
    $0 == e || $0 == le { if (!open || open != ($0 == e ? "current" : "legacy")) bad=1; open=""; next }
    END { if (open || bad) print "bad"; else if (seen) print "marked"; else print "unmarked" }
  ' "$INIT")"
  [[ "$result" != bad ]] || die "ambiguous Hammerspoon markers: $INIT"
  if [[ "$result" == unmarked ]]; then
    if grep -q 'iina_qol\|IINA QOL' "$INIT"; then
      die "unmarked IINA loader needs manual review: $INIT"
    fi
  fi
}
strip_markers() {
  awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" -v lb="$LEGACY_BEGIN" -v le="$LEGACY_END" '
    $0 == b || $0 == lb { inside=1; next }
    $0 == e || $0 == le { inside=0; next }
    !inside { print }
  ' "$INIT"
}
preflight() {
  [[ -f "$PROFILE" && -f "$MPV_SOURCE/mpv.conf" && -f "$MPV_SOURCE/shaders-pin.json" ]] || die 'missing native profile or mpv source'
  local path
  for path in "$PROFILE" "$MPV_SOURCE/mpv.conf" "$MPV_SOURCE/shaders-pin.json"; do
    check_parents "$path"
    regular_or_absent "$path"
  done
  for path in "$NEW_PROFILE" "$OLD_PROFILE" "$INIT" "$HAMMERSPOON/iina_qol.lua" "$HAMMERSPOON/iina_qol/gesture.lua" "$HAMMERSPOON/iina_qol/window.lua" "$MPV/mpv.conf" "$MPV/shaders-pin.json"; do
    check_parents "$path"
    regular_or_absent "$path"
  done
  check_parents "$PLUGIN"
  directory_or_absent "$PLUGIN"
  check_tree "$PLUGIN"
  check_parents "$STATE"
  directory_or_absent "$STATE"
  if [[ -d "$STATE" ]] && [[ ! -O "$STATE" ]]; then
    die "state directory must belong to the current user: $STATE"
  fi
  if [[ -e "$OLD_PROFILE" && -e "$NEW_PROFILE" ]] && ! cmp -s "$PROFILE" "$NEW_PROFILE"; then
    die "native profile already exists with different content: $NEW_PROFILE"
  fi
  check_markers
}
print_plan() {
  local path
  printf 'iina-native: native profile %s -> %s\n' "$PROFILE" "$NEW_PROFILE"
  for path in "$MPV_SOURCE/mpv.conf" "$MPV_SOURCE/shaders-pin.json"; do
    printf 'iina-native: native mpv %s -> %s/%s\n' "$path" "$MPV" "${path##*/}"
  done
  for path in "$OLD_PROFILE" "$PLUGIN" "$HAMMERSPOON/iina_qol.lua" "$HAMMERSPOON/iina_qol/gesture.lua" "$HAMMERSPOON/iina_qol/window.lua"; do
    if [[ -e "$path" ]]; then printf 'iina-native: backup then retire %s\n' "$path"; fi
  done
  if [[ -f "$INIT" ]]; then printf 'iina-native: remove marked QoL loader; preserve all other Hammerspoon init content %s\n' "$INIT"; fi
  printf 'iina-native: preserve all sibling plugins, global .data/.preferences, and downloaded shaders\n'
  printf 'iina-native: snapshot --apply copies named targets only; apply --backup PATH --apply requires that reviewed snapshot\n'
  printf 'iina-native: preference currentInputConfigName: IINA-Native; wheel=3/3, user config directory and other defaults require separate native/darwin validation\n'
}
# Fixed IDs are the entire restore vocabulary; no paths are read from backup metadata.
ids=(new_profile old_profile plugin init bridge gesture window mpv_conf shader_pin)
target_for() {
  case "$1" in
    new_profile) printf '%s' "$NEW_PROFILE" ;; old_profile) printf '%s' "$OLD_PROFILE" ;;
    plugin) printf '%s' "$PLUGIN" ;; init) printf '%s' "$INIT" ;;
    bridge) printf '%s' "$HAMMERSPOON/iina_qol.lua" ;;
    gesture) printf '%s' "$HAMMERSPOON/iina_qol/gesture.lua" ;;
    window) printf '%s' "$HAMMERSPOON/iina_qol/window.lua" ;;
    mpv_conf) printf '%s' "$MPV/mpv.conf" ;; shader_pin) printf '%s' "$MPV/shaders-pin.json" ;;
    *) die 'unknown snapshot identifier' ;;
  esac
}
create_backup() {
  local id path
  umask 077
  check_parents "$STATE"
  directory_or_absent "$STATE"
  mkdir -p "$STATE"
  BACKUP="$(mktemp -d "$STATE/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")"
  printf 'iina-native-v2\n' >"$BACKUP/version"
  for id in "${ids[@]}"; do
    path="$(target_for "$id")"
    if [[ -e "$path" ]]; then
      printf 'present\n' >"$BACKUP/$id.status"
      cp -R -p "$path" "$BACKUP/$id"
      if [[ "$id" == plugin ]]; then
        diff -qr "$path" "$BACKUP/$id" >/dev/null || die 'plugin changed while creating snapshot'
      else
        cmp -s "$path" "$BACKUP/$id" || die "target changed while creating snapshot: $path"
      fi
    else
      printf 'absent\n' >"$BACKUP/$id.status"
    fi
  done
  if command -v defaults >/dev/null 2>&1 && defaults read "$DOMAIN" currentInputConfigName >"$BACKUP/input-name" 2>/dev/null; then
    printf 'present\n' >"$BACKUP/input-name.status"
  else
    /bin/rm -f -- "$BACKUP/input-name"
    printf 'absent\n' >"$BACKUP/input-name.status"
  fi
  write_backup_manifest
  record_source_fingerprints
  validate_backup
  printf 'ready\n' >"$BACKUP/complete"
  printf 'iina-native: backup %s\n' "$BACKUP"
}
copy_atomic() {
  local src="$1" dest="$2" tmp
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp "$(dirname "$dest")/.iina-native.XXXXXX")"
  cp -p "$src" "$tmp"
  mv -f "$tmp" "$dest"
}
remove_named() {
  local path="$1"
  if [[ "$path" == "$PLUGIN" ]]; then
    [[ ! -e "$path" ]] || /bin/rm -R -- "$path"
  else
    [[ ! -e "$path" ]] || /bin/rm -f -- "$path"
  fi
}
record_source_fingerprints() {
  local source_file
  : >"$BACKUP/sources.sha256"
  for source_file in "$PROFILE" "$MPV_SOURCE/mpv.conf" "$MPV_SOURCE/shaders-pin.json"; do
    shasum -a 256 "$source_file" | cut -d ' ' -f 1 >>"$BACKUP/sources.sha256"
  done
}
verify_source_fingerprints() {
  local source_file expected actual index=0
  local -a source_hashes=()
  [[ -f "$BACKUP/sources.sha256" && ! -L "$BACKUP/sources.sha256" ]] || die 'backup lacks source fingerprints'
  while IFS= read -r expected; do source_hashes+=("$expected"); done <"$BACKUP/sources.sha256"
  [[ "${#source_hashes[@]}" -eq 3 ]] || die 'backup has incomplete source fingerprints'
  for source_file in "$PROFILE" "$MPV_SOURCE/mpv.conf" "$MPV_SOURCE/shaders-pin.json"; do
    expected="${source_hashes[$index]}"
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || die 'backup source fingerprint malformed'
    actual="$(shasum -a 256 "$source_file" | cut -d ' ' -f 1)"
    [[ "$actual" == "$expected" ]] || die "source changed since reviewed snapshot: $source_file"
    index=$((index + 1))
  done
}
write_backup_manifest() {
  uv run python - "$BACKUP" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
ids = ('new_profile', 'old_profile', 'plugin', 'init', 'bridge', 'gesture', 'window', 'mpv_conf', 'shader_pin')
entries = {}
for name in (*ids, 'input-name'):
    status = (root / f'{name}.status').read_text().strip()
    if status == 'absent':
        entries[name] = None
        continue
    target = root / name
    if target.is_file() and not target.is_symlink():
        entries[name] = {'.': hashlib.sha256(target.read_bytes()).hexdigest()}
    elif target.is_dir() and not target.is_symlink():
        files = {}
        for child in sorted(target.rglob('*')):
            if child.is_symlink() or not (child.is_dir() or child.is_file()):
                raise SystemExit(f'unsupported snapshot entry: {child}')
            relative = child.relative_to(target).as_posix()
            if child.is_dir():
                files[relative + '/'] = None
            else:
                files[relative] = hashlib.sha256(child.read_bytes()).hexdigest()
        entries[name] = files
    else:
        raise SystemExit(f'missing snapshot entry: {name}')
(root / 'manifest.json').write_text(json.dumps(entries, sort_keys=True, separators=(',', ':')) + '\n')
PY
}
validate_backup_manifest() {
  uv run python - "$BACKUP" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
ids = ('new_profile', 'old_profile', 'plugin', 'init', 'bridge', 'gesture', 'window', 'mpv_conf', 'shader_pin', 'input-name')
manifest = root / 'manifest.json'
if manifest.is_symlink() or not manifest.is_file():
    raise SystemExit('missing or symlinked snapshot manifest')
try:
    entries = json.loads(manifest.read_text())
except (OSError, ValueError) as exc:
    raise SystemExit(f'invalid snapshot manifest: {exc}')
if not isinstance(entries, dict) or set(entries) != set(ids):
    raise SystemExit('incomplete snapshot manifest')
for name in ids:
    status = (root / f'{name}.status').read_text().strip()
    expected = entries[name]
    if status == 'absent':
        if expected is not None:
            raise SystemExit(f'absent snapshot has digest: {name}')
        continue
    target = root / name
    if target.is_file() and not target.is_symlink():
        actual = {'.': hashlib.sha256(target.read_bytes()).hexdigest()}
    elif target.is_dir() and not target.is_symlink():
        actual = {}
        for child in sorted(target.rglob('*')):
            if child.is_symlink() or not (child.is_file() or child.is_dir()):
                raise SystemExit(f'unsafe snapshot entry: {child}')
            relative = child.relative_to(target).as_posix()
            if child.is_dir():
                actual[relative + '/'] = None
            else:
                actual[relative] = hashlib.sha256(child.read_bytes()).hexdigest()
    else:
        raise SystemExit(f'missing snapshot content: {name}')
    if actual != expected:
        raise SystemExit(f'snapshot content mismatch: {name}')
PY
}
validate_backup() {
  local id status path
  [[ -n "$BACKUP" && -d "$BACKUP" && ! -L "$BACKUP" && -O "$BACKUP" ]] || die 'supply an owned existing --backup directory'
  check_parents "$BACKUP"
  [[ "$(dirname "$BACKUP")" == "$STATE" && "$(basename "$BACKUP")" =~ ^[0-9]{8}T[0-9]{6}Z\.[A-Za-z0-9]+$ ]] || die 'backup must be a direct child of the configured state directory'
  [[ -f "$BACKUP/version" && ! -L "$BACKUP/version" && "$(<"$BACKUP/version")" == iina-native-v2 ]] || die 'unsupported backup format'
  [[ ! -e "$BACKUP/complete" || (-f "$BACKUP/complete" && ! -L "$BACKUP/complete" && "$(<"$BACKUP/complete")" == ready) ]] || die 'invalid completion marker'
  [[ ! -e "$BACKUP/dirty" || (-f "$BACKUP/dirty" && ! -L "$BACKUP/dirty" && "$(<"$BACKUP/dirty")" == apply-in-progress) ]] || die 'invalid dirty marker'
  [[ ! -e "$BACKUP/restore-dirty" || (-f "$BACKUP/restore-dirty" && ! -L "$BACKUP/restore-dirty" && "$(<"$BACKUP/restore-dirty")" == restore-in-progress) ]] || die 'invalid restore dirty marker'
  for id in "${ids[@]}"; do
    [[ -f "$BACKUP/$id.status" && ! -L "$BACKUP/$id.status" ]] || die "missing backup status: $id"
    status="$(<"$BACKUP/$id.status")"
    [[ "$status" == present || "$status" == absent ]] || die "invalid backup status: $id"
    if [[ "$status" == absent && (-e "$BACKUP/$id" || -L "$BACKUP/$id") ]]; then
      die "unexpected content for absent backup: $id"
    fi
    path="$(target_for "$id")"
    check_parents "$path"
    if [[ "$id" == plugin ]]; then directory_or_absent "$path"; else regular_or_absent "$path"; fi
    if [[ "$status" == present ]]; then
      [[ -e "$BACKUP/$id" && ! -L "$BACKUP/$id" ]] || die "missing backup content: $id"
      if [[ "$id" == plugin ]]; then
        [[ -d "$BACKUP/$id" ]] || die 'invalid plugin backup'
        check_tree "$BACKUP/$id"
      else
        [[ -f "$BACKUP/$id" ]] || die "invalid file backup: $id"
      fi
    fi
  done
  [[ -f "$BACKUP/input-name.status" && ! -L "$BACKUP/input-name.status" ]] || die 'missing preference status'
  status="$(<"$BACKUP/input-name.status")"
  [[ "$status" == present || "$status" == absent ]] || die 'invalid preference status'
  if [[ "$status" == present ]]; then
    [[ -f "$BACKUP/input-name" && ! -L "$BACKUP/input-name" ]] || die 'missing preference backup'
  elif [[ -e "$BACKUP/input-name" || -L "$BACKUP/input-name" ]]; then
    die 'unexpected preference content for absent backup'
  fi
  local entry name
  for entry in "$BACKUP"/* "$BACKUP"/.[!.]*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    name="${entry##*/}"
    case "$name" in
      version | complete | dirty | restore-dirty | sources.sha256 | manifest.json | input-name | input-name.status | new_profile | new_profile.status | old_profile | old_profile.status | plugin | plugin.status | init | init.status | bridge | bridge.status | gesture | gesture.status | window | window.status | mpv_conf | mpv_conf.status | shader_pin | shader_pin.status) ;;
      *) die "unexpected backup entry: $name" ;;
    esac
  done
  validate_backup_manifest || die 'backup content verification failed'
  [[ -f "$BACKUP/sources.sha256" && ! -L "$BACKUP/sources.sha256" ]] || die 'backup lacks source fingerprints'
  [[ "$(wc -l <"$BACKUP/sources.sha256" | tr -d ' ')" == 3 ]] || die 'backup has incomplete source fingerprints'
  local fingerprint
  while IFS= read -r fingerprint; do
    [[ "$fingerprint" =~ ^[0-9a-f]{64}$ ]] || die 'backup source fingerprint malformed'
  done <"$BACKUP/sources.sha256"
}
already_migrated() {
  local path
  [[ -f "$NEW_PROFILE" ]] && cmp -s "$PROFILE" "$NEW_PROFILE" || return 1
  [[ -f "$MPV/mpv.conf" ]] && cmp -s "$MPV_SOURCE/mpv.conf" "$MPV/mpv.conf" || return 1
  [[ -f "$MPV/shaders-pin.json" ]] && cmp -s "$MPV_SOURCE/shaders-pin.json" "$MPV/shaders-pin.json" || return 1
  for path in "$OLD_PROFILE" "$PLUGIN" "$HAMMERSPOON/iina_qol.lua" "$HAMMERSPOON/iina_qol/gesture.lua" "$HAMMERSPOON/iina_qol/window.lua"; do
    [[ ! -e "$path" ]] || return 1
  done
  if [[ -f "$INIT" ]] && grep -F -q -e "$BEGIN_MARKER" -e "$LEGACY_BEGIN" "$INIT"; then return 1; fi
  if command -v defaults >/dev/null 2>&1; then
    [[ "$(defaults read "$DOMAIN" currentInputConfigName 2>/dev/null || true)" == IINA-Native ]] || return 1
  fi
}
qol_identity_confirmed() {
  [[ -d "$PLUGIN" ]] || return 0
  [[ -f "$PLUGIN/Info.json" && ! -L "$PLUGIN/Info.json" ]] || return 1
  # The live permission-list manifest has no identifier. Only the exact public
  # code/UI bytes from the previously tracked QoL source qualify as provenance.
  local manifest_hash
  command -v shasum >/dev/null 2>&1 || return 1
  manifest_hash="$(shasum -a 256 "$PLUGIN/Info.json" | cut -d ' ' -f 1)" || return 1
  # A permission list has no identifier; the historical object does. Neither
  # shape alone is evidence: require the exact public manifest and code/UI.
  case "$manifest_hash" in
    017ac2e024d54718200d92a9fd13dfc247746783f5a0b02dc560f35a5e10e45e | c42ea168f978189e00053e74111e94e405d10e8b2a03e220f9456808704550f1) ;;
    *) return 1 ;;
  esac
  local name expected actual
  while IFS=' ' read -r expected name; do
    [[ -f "$PLUGIN/$name" && ! -L "$PLUGIN/$name" ]] || return 1
    actual="$(shasum -a 256 "$PLUGIN/$name" | cut -d ' ' -f 1)" || return 1
    [[ "$actual" == "$expected" ]] || return 1
  done <<'HASHES'
a78aca30fe34f0daa395e518539f244d8957866bc56478c4a2ae2598dc337368 main.js
5831a0d5f42c4618751b152dcfc23ac7a63966f158f0669330870d9c037f173b lib/zoom.js
09903ff3609468166f2a5cb3c08ca16653494401a85096016c74d289eb14d68b lib/settings.js
c5a7adf67a25e6d44f85c2e0a29b56654e0ff706523e2d7e9a5b8a1d3c9c8488 help.html
20c326337d0c71b2730e1ab9a0545f06b67aeb03fa41c95bc8c473e5c9e3c84e preferences.html
HASHES
}
require_qol_identity() {
  qol_identity_confirmed || die 'QoL plugin identity unavailable; review the live target before migration'
}
report_native_readiness() {
  local key expected actual failed=0
  if [[ -d "$PLUGIN" ]]; then
    if qol_identity_confirmed; then
      printf 'iina-native: ready QoL plugin identity confirmed\n'
    else
      printf 'iina-native: blocked QoL plugin identity unavailable (manifest or historical code fingerprints do not match)\n'
      failed=1
    fi
  else
    printf 'iina-native: ready QoL plugin absent\n'
  fi
  if ! command -v pgrep >/dev/null 2>&1; then
    printf 'iina-native: blocked pgrep unavailable; cannot verify IINA quit\n'
    failed=1
  elif pgrep -x IINA >/dev/null 2>&1; then
    printf 'iina-native: blocked IINA is running; quit it before apply\n'
    failed=1
  else
    printf 'iina-native: ready IINA not running\n'
  fi
  if ! command -v defaults >/dev/null 2>&1; then
    printf 'iina-native: blocked macOS defaults unavailable; preference preflight not verified\n'
    return 1
  fi
  for key in horizontalScrollAction verticalScrollAction useUserDefinedConfDir userDefinedConfDir middleClickAction; do
    case "$key" in
      horizontalScrollAction | verticalScrollAction) expected=3 ;;
      useUserDefinedConfDir) expected=1 ;;
      userDefinedConfDir) expected="$MPV" ;;
      middleClickAction) expected=0 ;;
    esac
    actual="$(defaults read "$DOMAIN" "$key" 2>/dev/null || true)"
    if [[ "$actual" == "$expected" ]]; then
      printf 'iina-native: ready preference %s\n' "$key"
    else
      printf 'iina-native: blocked preference %s expected=%s actual=%s\n' "$key" "$expected" "${actual:-absent}"
      failed=1
    fi
  done
  [[ "$failed" -eq 0 ]]
}
require_native_preferences() {
  command -v defaults >/dev/null 2>&1 || die 'macOS defaults unavailable; configure native IINA preferences manually before applying'
  local key expected actual
  for key in horizontalScrollAction verticalScrollAction; do
    expected=3
    actual="$(defaults read "$DOMAIN" "$key" 2>/dev/null || true)"
    [[ "$actual" == "$expected" ]] || die "$key must already be $expected (found ${actual:-absent}); configure it in IINA before applying"
  done
  actual="$(defaults read "$DOMAIN" useUserDefinedConfDir 2>/dev/null || true)"
  [[ "$actual" == 1 ]] || die 'useUserDefinedConfDir must already be enabled in IINA before applying'
  actual="$(defaults read "$DOMAIN" userDefinedConfDir 2>/dev/null || true)"
  [[ "$actual" == "$MPV" ]] || die 'userDefinedConfDir must already point at the managed mpv directory'
  actual="$(defaults read "$DOMAIN" middleClickAction 2>/dev/null || true)"
  [[ "$actual" == 0 ]] || die 'middleClickAction must already be none (0) before applying'
}
recover_failed_apply() {
  local code="$1"
  trap - ERR
  trap '' INT TERM
  if [[ -n "$BACKUP" ]]; then
    if restore_snapshot; then
      /bin/rm -f -- "$BACKUP/dirty"
      clear_mutation_marker
      printf 'iina-native: recovered from %s after failure\n' "$BACKUP" >&2
    else
      printf 'iina-native: recovery failed; inspect %s\n' "$BACKUP" >&2
    fi
  fi
  exit "$code"
}
recover_failed_restore() {
  local code="$1"
  trap - ERR
  trap '' INT TERM
  BACKUP="$RESTORE_RESCUE"
  if restore_snapshot; then
    /bin/rm -f -- "$RESTORE_RESCUE/restore-dirty"
    clear_mutation_marker
    printf 'iina-native: interrupted restore recovered from pre-restore rescue %s\n' "$RESTORE_RESCUE" >&2
  else
    printf 'iina-native: recovery incomplete; inspect rescue %s and original %s\n' "$RESTORE_RESCUE" "$RESTORE_ORIGINAL" >&2
  fi
  exit "$code"
}
verify_reviewed_snapshot_matches_live() {
  local id path status live_status
  validate_backup
  [[ -f "$BACKUP/complete" && "$(<"$BACKUP/complete")" == ready ]] || die 'reviewed snapshot incomplete'
  [[ ! -e "$BACKUP/dirty" && ! -e "$BACKUP/restore-dirty" ]] || die 'reviewed snapshot has dirty marker'
  verify_source_fingerprints
  for id in "${ids[@]}"; do
    path="$(target_for "$id")"
    status="$(<"$BACKUP/$id.status")"
    live_status=absent
    [[ -e "$path" ]] && live_status=present
    [[ "$live_status" == "$status" ]] || die "live target changed since reviewed snapshot: $path"
    if [[ "$status" == present ]]; then
      if [[ "$id" == plugin ]]; then
        check_tree "$path"
        diff -qr "$BACKUP/$id" "$path" >/dev/null || die "live target changed since reviewed snapshot: $path"
      else
        cmp -s "$BACKUP/$id" "$path" || die "live target changed since reviewed snapshot: $path"
      fi
    fi
  done
  live_status="$(defaults read "$DOMAIN" currentInputConfigName 2>/dev/null || true)"
  status="$(<"$BACKUP/input-name.status")"
  if [[ "$status" == present ]]; then
    [[ "$live_status" == "$(<"$BACKUP/input-name")" ]] || die 'active profile changed since reviewed snapshot'
  else
    [[ -z "$live_status" ]] || die 'active profile changed since reviewed snapshot'
  fi
}
restore_snapshot() {
  local id path status
  validate_backup
  [[ -f "$BACKUP/complete" && "$(<"$BACKUP/complete")" == ready ]] || die 'backup is incomplete; refusing restore'
  for id in "${ids[@]}"; do
    path="$(target_for "$id")"
    status="$(<"$BACKUP/$id.status")"
    remove_named "$path" || return 1
    if [[ "$status" == present ]]; then
      mkdir -p "$(dirname "$path")" || return 1
      cp -R -p "$BACKUP/$id" "$path" || return 1
    fi
  done
  if command -v defaults >/dev/null 2>&1; then
    if [[ "$(<"$BACKUP/input-name.status")" == present ]]; then
      defaults write "$DOMAIN" currentInputConfigName -string "$(<"$BACKUP/input-name")" || return 1
    else
      defaults delete "$DOMAIN" currentInputConfigName >/dev/null 2>&1 || true
    fi
  fi
}
case "$CMD" in
  preview | doctor)
    preflight
    print_plan
    if [[ "$CMD" == doctor ]]; then
      if [[ -f "$NEW_PROFILE" ]] && cmp -s "$PROFILE" "$NEW_PROFILE"; then
        printf 'iina-native: profile in sync\n'
      else
        printf 'iina-native: profile not installed or drifted (expected before migration)\n'
      fi
      report_native_readiness || exit 1
    fi
    ;;
  snapshot)
    preflight
    print_plan
    if [[ "$APPLY" -eq 0 ]]; then
      printf 'iina-native: dry-run; use snapshot --apply to copy only the named backup targets\n'
      exit 0
    fi
    [[ -z "$BACKUP" ]] || die 'snapshot creates a new state path; omit --backup'
    acquire_mutation_lock
    require_iina_quit
    require_qol_identity
    require_native_preferences
    create_backup
    verify_reviewed_snapshot_matches_live
    printf 'iina-native: review snapshot and then request separate migration approval; backup=%s\n' "$BACKUP"
    ;;
  apply)
    preflight
    print_plan
    if [[ "$APPLY" -eq 0 ]]; then
      printf 'iina-native: dry-run; use apply --apply\n'
      exit 0
    fi
    require_iina_quit
    require_qol_identity
    require_native_preferences
    if already_migrated; then
      printf 'iina-native: already migrated; no changes\n'
      exit 0
    fi
    [[ -n "$BACKUP" ]] || die 'apply --apply requires --backup PATH from a separately reviewed snapshot'
    acquire_mutation_lock
    verify_reviewed_snapshot_matches_live
    require_iina_quit
    trap 'recover_failed_apply "$?"' ERR
    trap 'recover_failed_apply 130' INT
    trap 'recover_failed_apply 143' TERM
    mark_mutation_started "apply:$BACKUP"
    printf 'apply-in-progress\n' >"$BACKUP/dirty"
    copy_atomic "$PROFILE" "$NEW_PROFILE"
    copy_atomic "$MPV_SOURCE/mpv.conf" "$MPV/mpv.conf"
    copy_atomic "$MPV_SOURCE/shaders-pin.json" "$MPV/shaders-pin.json"
    if [[ -f "$INIT" ]] && grep -F -q -e "$BEGIN_MARKER" -e "$LEGACY_BEGIN" "$INIT"; then
      temp="$(mktemp "$(dirname "$INIT")/.iina-native.XXXXXX")"
      strip_markers >"$temp"
      mv -f "$temp" "$INIT"
    fi
    remove_named "$OLD_PROFILE"
    remove_named "$PLUGIN"
    remove_named "$HAMMERSPOON/iina_qol.lua"
    remove_named "$HAMMERSPOON/iina_qol/gesture.lua"
    remove_named "$HAMMERSPOON/iina_qol/window.lua"
    if command -v defaults >/dev/null 2>&1; then defaults write "$DOMAIN" currentInputConfigName -string IINA-Native; fi
    /bin/rm -f -- "$BACKUP/dirty"
    clear_mutation_marker
    trap - ERR INT TERM
    printf 'iina-native: migrated; restore with restore --backup %s --apply\n' "$BACKUP"
    ;;
  restore)
    [[ -n "$BACKUP" ]] || die 'restore requires --backup PATH'
    validate_backup
    [[ -f "$BACKUP/complete" && "$(<"$BACKUP/complete")" == ready ]] || die 'backup is incomplete; refusing restore'
    [[ ! -e "$BACKUP/dirty" && ! -e "$BACKUP/restore-dirty" ]] || die 'backup has a dirty marker; inspect before restoring'
    printf 'iina-native: restore snapshot %s\n' "$BACKUP"
    if [[ "$APPLY" -eq 0 ]]; then
      printf 'iina-native: dry-run; use restore --backup PATH --apply\n'
      exit 0
    fi
    acquire_mutation_lock
    require_iina_quit
    RESTORE_ORIGINAL="$BACKUP"
    create_backup
    RESTORE_RESCUE="$BACKUP"
    BACKUP="$RESTORE_ORIGINAL"
    trap 'recover_failed_restore "$?"' ERR
    trap 'recover_failed_restore 130' INT
    trap 'recover_failed_restore 143' TERM
    mark_mutation_started "restore:$BACKUP"
    printf 'restore-in-progress\n' >"$RESTORE_RESCUE/restore-dirty"
    restore_snapshot
    /bin/rm -f -- "$RESTORE_RESCUE/restore-dirty"
    clear_mutation_marker
    trap - ERR INT TERM
    printf 'iina-native: restored %s (pre-restore rescue %s)\n' "$BACKUP" "$RESTORE_RESCUE"
    ;;
esac
