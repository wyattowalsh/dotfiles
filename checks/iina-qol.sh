#!/usr/bin/env bash
# Exact-target IINA QoL preview/apply/doctor/restore. Default is dry-run.
# Uses $HOME and $REPO; never chezmoi-applies the whole home tree.
set -euo pipefail

REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HOME_ROOT="${IINA_QOL_HOME_ROOT:-$REPO/rig/home}"
HS_SRC="$HOME_ROOT/dot_hammerspoon"
IINA_SRC="$HOME_ROOT/Library/Application Support/com.colliderli.iina"
PLUGIN_SRC="$IINA_SRC/plugins/IINA-QoL.iinaplugin"
CONF_SRC="$IINA_SRC/input_conf/IINA-QoL.conf"
NIX_DEFAULTS="$REPO/rig/darwin/modules/macos-defaults.nix"

HS_DEST="${IINA_QOL_HAMMERSPOON_DEST:-$HOME/.hammerspoon}"
IINA_DEST="${IINA_QOL_IINA_DEST:-$HOME/Library/Application Support/com.colliderli.iina}"
PLUGIN_DEST="$IINA_DEST/plugins/IINA-QoL.iinaplugin"
CONF_DEST="$IINA_DEST/input_conf/IINA-QoL.conf"
STATE_ROOT="${IINA_QOL_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/iina-qol}"
DEFAULTS_DOMAIN="${IINA_QOL_DEFAULTS_DOMAIN:-com.colliderli.iina}"

MARKER_BEGIN='-- >>> IINA QOL >>>'
MARKER_END='-- <<< IINA QOL <<<'
MARKER_BEGIN_LEGACY='-- >>> IINA QOL SCROLL ZOOM >>>'
MARKER_END_LEGACY='-- <<< IINA QOL SCROLL ZOOM <<<'
DOCTOR_URL='hammerspoon://iina-qol?action=doctor'

APPLY=0
CMD=""

# key<TAB>defaults-type<TAB>desired-value
DEFAULT_SPECS=(
  $'currentInputConfigName\tstring\tIINA-QoL'
  $'horizontalScrollAction\tint\t1'
  $'verticalScrollAction\tint\t4'
  $'playbackSpeedScrollAmount\tint\t3'
  $'screenshotSaveToFile\tbool\ttrue'
  $'screenshotCopyToClipboard\tbool\ttrue'
  $'screenShotIncludeSubtitle\tbool\ttrue'
  $'screenshotShowPreview\tbool\ttrue'
  $'screenShotFormat\tint\t0'
  $'useMediaKeys\tbool\ttrue'
  $'enableAdvancedSettings\tbool\ttrue'
)

usage() {
  cat <<'EOF'
Usage: checks/iina-qol.sh [preview|apply|doctor|restore] [--apply|--dry-run]

preview   Print src vs dest for Hammerspoon, plugin, input_conf, and IINA defaults (default)
apply     Copy tracked files to dest; requires --apply to mutate
doctor    Trigger Hammerspoon/IINA doctor if hs or open is available
restore   Restore the latest timestamped backup; requires --apply to mutate

Default without --apply is dry-run. Does not chezmoi-apply the whole home tree.
EOF
}

die() {
  printf 'iina-qol: %s\n' "$*" >&2
  exit 1
}

relpath() {
  local path="$1"
  printf '%s\n' "${path#"$REPO"/}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    preview | apply | doctor | restore)
      if [[ -n "$CMD" ]]; then
        die "multiple subcommands: $CMD and $1"
      fi
      CMD="$1"
      shift
      ;;
    --apply)
      APPLY=1
      shift
      ;;
    --dry-run)
      APPLY=0
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'iina-qol: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

CMD="${CMD:-preview}"

skip_defaults() {
  [[ "${IINA_QOL_SKIP_DEFAULTS:-}" == "1" ]]
}

collect_sorted_files() {
  local root="$1"
  if [[ ! -d "$root" ]]; then
    return 0
  fi
  (
    cd "$root"
    find . -type f ! -name '.DS_Store' ! -name 'AGENTS.md' \
      ! -name 'history.plist' ! -name '*.log' \
      ! -path '*/.data/*' ! -path '*/.preferences/*' ! -path '*/watch_later/*' \
      ! -path '*/screenshots/*' | sed 's|^\./||' | LC_ALL=C sort
  )
}

require_sources() {
  [[ -f "$HS_SRC/init.lua" ]] || die "missing source $(relpath "$HS_SRC/init.lua")"
  [[ -f "$HS_SRC/iina_qol.lua" ]] || die "missing source $(relpath "$HS_SRC/iina_qol.lua")"
  [[ -f "$CONF_SRC" ]] || die "missing source $(relpath "$CONF_SRC")"
  [[ -f "$PLUGIN_SRC/Info.json" ]] || die "missing source $(relpath "$PLUGIN_SRC/Info.json")"
  [[ -f "$PLUGIN_SRC/main.js" ]] || die "missing source $(relpath "$PLUGIN_SRC/main.js")"
  [[ -f "$PLUGIN_SRC/lib/zoom.js" ]] || die "missing source $(relpath "$PLUGIN_SRC/lib/zoom.js")"
  [[ -f "$PLUGIN_SRC/lib/settings.js" ]] || die "missing source $(relpath "$PLUGIN_SRC/lib/settings.js")"
  if [[ -d "$HS_SRC/iina_qol" ]]; then
    [[ -f "$HS_SRC/iina_qol/gesture.lua" ]] || die "missing source $(relpath "$HS_SRC/iina_qol/gesture.lua")"
    [[ -f "$HS_SRC/iina_qol/window.lua" ]] || die "missing source $(relpath "$HS_SRC/iina_qol/window.lua")"
  else
    [[ -f "$HS_SRC/iina_qol_gesture.lua" ]] || die "missing source $(relpath "$HS_SRC/iina_qol_gesture.lua")"
    [[ -f "$HS_SRC/iina_qol_window.lua" ]] || die "missing source $(relpath "$HS_SRC/iina_qol_window.lua")"
  fi
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    [[ -f "$PLUGIN_SRC/$path" ]] || die "missing plugin source $(relpath "$PLUGIN_SRC/$path")"
  done < <(collect_sorted_files "$PLUGIN_SRC")
}

outside_markers() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    return 0
  fi
  awk -v b1="$MARKER_BEGIN" -v e1="$MARKER_END" -v b2="$MARKER_BEGIN_LEGACY" -v e2="$MARKER_END_LEGACY" '
    $0 == b1 || $0 == b2 { inside = 1; next }
    $0 == e1 || $0 == e2 { inside = 0; next }
    !inside { print }
  ' "$path"
}

# Abort apply when dest init.lua has unmarked content that is not in source.
assert_init_merge_safe() {
  local dest="$HS_DEST/init.lua"
  local src="$HS_SRC/init.lua"
  local dest_outside src_outside line
  if [[ ! -f "$dest" ]]; then
    return 0
  fi
  dest_outside="$(outside_markers "$dest" | sed '/^[[:space:]]*$/d')"
  src_outside="$(outside_markers "$src" | sed '/^[[:space:]]*$/d')"
  if [[ -z "$dest_outside" ]]; then
    return 0
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if ! printf '%s\n' "$src_outside" | rg -F -x -q -- "$line"; then
      die "refuse apply: $dest has content outside IINA QOL markers that is not in source (explicit merge required)"
    fi
  done <<<"$dest_outside"
}

print_pair() {
  local kind="$1"
  local src="$2"
  local dest="$3"
  local src_state dest_state
  if [[ -e "$src" ]]; then
    src_state="present"
  else
    src_state="missing"
  fi
  if [[ -e "$dest" ]]; then
    dest_state="present"
  else
    dest_state="missing"
  fi
  printf 'iina-qol: %-12s src=%s (%s)\n' "$kind" "$src" "$src_state"
  printf 'iina-qol: %-12s dest=%s (%s)\n' "$kind" "$dest" "$dest_state"
}

read_defaults_dest() {
  local key="$1"
  if skip_defaults || ! command -v defaults >/dev/null 2>&1; then
    printf '%s\n' 'unavailable'
    return 0
  fi
  if ! defaults read "$DEFAULTS_DOMAIN" "$key" >/dev/null 2>&1; then
    printf '%s\n' 'absent'
    return 0
  fi
  defaults read "$DEFAULTS_DOMAIN" "$key"
}

print_defaults_preview() {
  local spec key type wanted dest
  printf 'iina-qol: defaults domain=%s\n' "$DEFAULTS_DOMAIN"
  for spec in "${DEFAULT_SPECS[@]}"; do
    key="${spec%%$'\t'*}"
    type="${spec#*$'\t'}"
    type="${type%%$'\t'*}"
    wanted="${spec##*$'\t'}"
    dest="$(read_defaults_dest "$key")"
    printf 'iina-qol: defaults %-28s src=%s dest=%s type=%s\n' "$key" "$wanted" "$dest" "$type"
  done
  if [[ -f "$NIX_DEFAULTS" ]]; then
    printf 'iina-qol: defaults nix-src=%s (present)\n' "$NIX_DEFAULTS"
  else
    printf 'iina-qol: defaults nix-src=%s (missing)\n' "$NIX_DEFAULTS"
  fi
}

print_tree_preview() {
  local rel
  printf 'iina-qol: preview cmd=%s apply=%s repo=%s home=%s\n' "$CMD" "$APPLY" "$REPO" "$HOME"
  print_pair hammerspoon "$HS_SRC" "$HS_DEST"
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    print_pair "hs:$rel" "$HS_SRC/$rel" "$HS_DEST/$rel"
  done < <(collect_sorted_files "$HS_SRC")
  print_pair plugin "$PLUGIN_SRC" "$PLUGIN_DEST"
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    print_pair "plugin:$rel" "$PLUGIN_SRC/$rel" "$PLUGIN_DEST/$rel"
  done < <(collect_sorted_files "$PLUGIN_SRC")
  print_pair input_conf "$CONF_SRC" "$CONF_DEST"
  print_defaults_preview
}

backup_if_present() {
  local dest="$1"
  local rel="$2"
  local target
  if [[ "$APPLY" -eq 0 || ! -e "$dest" ]]; then
    return 0
  fi
  target="$BACKUP_DIR/$rel"
  mkdir -p "$(dirname "$target")"
  cp -p "$dest" "$target"
  printf 'iina-qol: backup %s\n' "$target"
}

plan_copy() {
  local src="$1"
  local dest="$2"
  if [[ "$APPLY" -eq 1 ]]; then
    printf 'iina-qol: copy %s -> %s\n' "$(relpath "$src")" "$dest"
  else
    printf 'iina-qol: dry-run copy %s -> %s\n' "$(relpath "$src")" "$dest"
  fi
}

apply_file() {
  local src="$1"
  local dest="$2"
  local rel="$3"
  plan_copy "$src" "$dest"
  if [[ "$APPLY" -eq 0 ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  if [[ -e "$dest" ]]; then
    backup_if_present "$dest" "$rel"
  else
    printf '%s\n' "$dest" >>"$BACKUP_DIR/absent.txt"
  fi
  cp -p "$src" "$dest"
}

backup_defaults() {
  local spec key type dest out
  if skip_defaults || ! command -v defaults >/dev/null 2>&1; then
    return 0
  fi
  out="$BACKUP_DIR/defaults.tsv"
  if [[ "$APPLY" -eq 0 ]]; then
    printf 'iina-qol: dry-run backup defaults %s\n' "$out"
    return 0
  fi
  mkdir -p "$BACKUP_DIR"
  : >"$out"
  for spec in "${DEFAULT_SPECS[@]}"; do
    key="${spec%%$'\t'*}"
    type="${spec#*$'\t'}"
    type="${type%%$'\t'*}"
    if ! defaults read "$DEFAULTS_DOMAIN" "$key" >/dev/null 2>&1; then
      printf '%s\tabsent\t\n' "$key" >>"$out"
      continue
    fi
    dest="$(defaults read "$DEFAULTS_DOMAIN" "$key")"
    printf '%s\t%s\t%s\n' "$key" "$type" "$dest" >>"$out"
  done
  printf 'iina-qol: backup defaults %s\n' "$out"
}

write_desired_defaults() {
  local spec key type wanted
  if skip_defaults || ! command -v defaults >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$APPLY" -eq 0 ]]; then
    printf 'iina-qol: dry-run would write pinned %s keys\n' "$DEFAULTS_DOMAIN"
    return 0
  fi
  for spec in "${DEFAULT_SPECS[@]}"; do
    key="${spec%%$'\t'*}"
    type="${spec#*$'\t'}"
    type="${type%%$'\t'*}"
    wanted="${spec##*$'\t'}"
    case "$type" in
      string) defaults write "$DEFAULTS_DOMAIN" "$key" -string "$wanted" ;;
      int) defaults write "$DEFAULTS_DOMAIN" "$key" -int "$wanted" ;;
      bool) defaults write "$DEFAULTS_DOMAIN" "$key" -bool "$wanted" ;;
      *) die "unknown defaults type $type for $key" ;;
    esac
    printf 'iina-qol: defaults write %s %s (%s)\n' "$key" "$wanted" "$type"
  done
}

cmd_preview() {
  require_sources
  print_tree_preview
  printf 'iina-qol: ok (preview)\n'
}

cmd_apply() {
  local rel
  require_sources
  assert_init_merge_safe
  print_tree_preview
  if [[ "$APPLY" -eq 1 ]]; then
    mkdir -p "$STATE_ROOT"
    BACKUP_DIR="$(
      umask 077
      mktemp -d "$STATE_ROOT/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX"
    )"
    printf 'iina-qol: backup-dir %s\n' "$BACKUP_DIR"
  else
    printf 'iina-qol: dry-run backup-dir %s\n' "$BACKUP_DIR"
  fi
  backup_defaults
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    apply_file "$HS_SRC/$rel" "$HS_DEST/$rel" "hammerspoon/$rel"
  done < <(collect_sorted_files "$HS_SRC")
  apply_file "$CONF_SRC" "$CONF_DEST" "iina/input_conf/IINA-QoL.conf"
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    apply_file "$PLUGIN_SRC/$rel" "$PLUGIN_DEST/$rel" "iina/plugins/IINA-QoL.iinaplugin/$rel"
  done < <(collect_sorted_files "$PLUGIN_SRC")
  write_desired_defaults
  if [[ "$APPLY" -eq 1 ]]; then
    printf 'iina-qol: ok\n'
  else
    printf 'iina-qol: ok (dry-run)\n'
  fi
}

cmd_doctor() {
  local triggered=0
  if command -v hs >/dev/null 2>&1; then
    if hs -c 'hs.urlevent.openURL("hammerspoon://iina-qol?action=doctor")' >/dev/null 2>&1; then
      printf 'iina-qol: triggered doctor via hs CLI\n'
      triggered=1
    fi
  fi
  if [[ "$triggered" -eq 0 ]] && command -v open >/dev/null 2>&1; then
    if open "$DOCTOR_URL" >/dev/null 2>&1; then
      printf 'iina-qol: triggered doctor via open %s\n' "$DOCTOR_URL"
      triggered=1
    fi
  fi
  if [[ "$triggered" -eq 0 ]]; then
    cat <<EOF
iina-qol: doctor not triggered (hs CLI / open hammerspoon URL unavailable).
  Try: hs -c 'hs.urlevent.openURL("hammerspoon://iina-qol?action=doctor")'
  Or:  open "$DOCTOR_URL"
  Or:  press F15 in IINA with plugin com.wyattowalsh.iina-qol enabled
EOF
  fi
}

latest_backup_dir() {
  if [[ ! -d "$STATE_ROOT" ]]; then
    return 1
  fi
  find "$STATE_ROOT" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort | tail -n 1
}

restore_file() {
  local src="$1"
  local dest="$2"
  if [[ "$APPLY" -eq 1 ]]; then
    printf 'iina-qol: restore %s -> %s\n' "$src" "$dest"
    mkdir -p "$(dirname "$dest")"
    cp -p "$src" "$dest"
  else
    printf 'iina-qol: dry-run restore %s -> %s\n' "$src" "$dest"
  fi
}

restore_defaults_from_backup() {
  local tsv="$1"
  local key type value
  if skip_defaults || ! command -v defaults >/dev/null 2>&1; then
    return 0
  fi
  if [[ ! -f "$tsv" ]]; then
    return 0
  fi
  while IFS=$'\t' read -r key type value; do
    [[ -n "$key" ]] || continue
    if [[ "$APPLY" -eq 0 ]]; then
      printf 'iina-qol: dry-run restore defaults %s (%s)\n' "$key" "$type"
      continue
    fi
    case "$type" in
      absent)
        defaults delete "$DEFAULTS_DOMAIN" "$key" >/dev/null 2>&1 || true
        printf 'iina-qol: defaults delete %s (was absent)\n' "$key"
        ;;
      string)
        defaults write "$DEFAULTS_DOMAIN" "$key" -string "$value"
        printf 'iina-qol: defaults restore %s string\n' "$key"
        ;;
      int)
        defaults write "$DEFAULTS_DOMAIN" "$key" -int "$value"
        printf 'iina-qol: defaults restore %s int\n' "$key"
        ;;
      bool)
        defaults write "$DEFAULTS_DOMAIN" "$key" -bool "$value"
        printf 'iina-qol: defaults restore %s bool\n' "$key"
        ;;
      *)
        die "unknown backup defaults type $type for $key"
        ;;
    esac
  done <"$tsv"
}

cmd_restore() {
  local backup rel
  backup="$(latest_backup_dir || true)"
  if [[ -z "$backup" ]]; then
    die "no backups under $STATE_ROOT"
  fi
  printf 'iina-qol: restore from %s apply=%s\n' "$backup" "$APPLY"
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    case "$rel" in
      hammerspoon/*)
        restore_file "$backup/$rel" "$HS_DEST/${rel#hammerspoon/}"
        ;;
      iina/*)
        restore_file "$backup/$rel" "$IINA_DEST/${rel#iina/}"
        ;;
      defaults.tsv | absent.txt) ;;
      *)
        printf 'iina-qol: skip unknown backup path %s\n' "$rel"
        ;;
    esac
  done < <(collect_sorted_files "$backup")
  if [[ -f "$backup/absent.txt" ]]; then
    while IFS= read -r dest; do
      [[ -n "$dest" ]] || continue
      if [[ "$APPLY" -eq 1 ]]; then
        rm -f "$dest"
        printf 'iina-qol: restore remove %s (was absent)\n' "$dest"
      else
        printf 'iina-qol: dry-run restore remove %s (was absent)\n' "$dest"
      fi
    done <"$backup/absent.txt"
  fi
  restore_defaults_from_backup "$backup/defaults.tsv"
  if [[ "$APPLY" -eq 1 ]]; then
    printf 'iina-qol: ok\n'
  else
    printf 'iina-qol: ok (dry-run)\n'
  fi
}

BACKUP_DIR="$STATE_ROOT/$(date -u +%Y%m%dT%H%M%SZ)"

case "$CMD" in
  preview) cmd_preview ;;
  apply) cmd_apply ;;
  doctor) cmd_doctor ;;
  restore) cmd_restore ;;
  *)
    die "unknown subcommand $CMD"
    ;;
esac
