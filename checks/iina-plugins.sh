#!/usr/bin/env bash
# Pinned official IINA plugin installer. Downloads release packages; never vendors them.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" # Never execute from a downloaded archive or a caller-controlled directory.
PIN="${IINA_PLUGINS_PIN:-$ROOT/rig/home/Library/Application Support/com.colliderli.iina/official-plugins-pin.json}"
PLUGIN_ROOT="${IINA_PLUGINS_DEST:-$HOME/Library/Application Support/com.colliderli.iina/plugins}"
STATE_ROOT="${IINA_PLUGINS_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/iina-plugins}"
CMD=""
APPLY=0
WORK_DIR=""
BACKUP=""
INSTALL_ACTIVE=0
RESTORE_ACTIVE=0
RESCUE=""

acquire_operation_lock() {
  command -v flock >/dev/null 2>&1 || die 'flock unavailable; refusing mutation'
  local lock="${IINA_OPERATION_LOCK:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/.iina-operation.lock}"
  mkdir -p "$(dirname "$lock")"
  [[ ! -L "$lock" ]] || die 'symlinked operation lock refused'
  exec 9>"$lock"
  flock -n 9 || die 'another IINA operation is running'
}

cleanup() {
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    rm -rf -- "$WORK_DIR"
  fi
}

usage() {
  cat <<'EOF'
Usage: checks/iina-plugins.sh [preview|install|doctor|restore] [--apply|--dry-run]

preview   Validate and show the pinned official plugin releases (default)
install   Download, verify, and install all pinned official plugins
           (requires --apply to mutate; quit IINA first)
doctor    Compare live official plugin versions to the pin
restore   Restore the latest pre-install snapshot (requires --apply)

Packages come from official iina/* GitHub release assets, are hash-checked, and
remain untracked. Plugin runtime preferences/data are not changed.
EOF
}

die() {
  printf 'iina-plugins: %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    preview | install | doctor | restore)
      [[ -z "$CMD" ]] || die "multiple subcommands: $CMD and $1"
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
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
done
CMD="${CMD:-preview}"

validate_pin() {
  [[ -f "$PIN" ]] || die "missing pin: $PIN"
  UV_NO_PROJECT=1 uv run --offline --no-project python -I - "$PIN" <<'PY' || die "invalid plugin pin"
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except (OSError, json.JSONDecodeError) as exc:
    print(exc, file=sys.stderr)
    raise SystemExit(1)

errors = []
if data.get("version") != 1:
    errors.append("version must be 1")
plugins = data.get("plugins")
if not isinstance(plugins, list) or not plugins:
    errors.append("plugins must be a non-empty list")
    plugins = []
expected = {
    "io.iina.ytdl": ("io.iina.ytdl.iinaplugin", "iina/plugin-online-media", "iina-plugin-ytdl"),
    "io.iina.opensub": ("io.iina.opensub.iinaplugin", "iina/plugin-opensub", "iina-plugin-opensub"),
    "io.iina.user-script": ("io.iina.user-script.iinaplugin", "iina/plugin-userscript", "iina-plugin-userscript"),
}
seen = set()
seen_destinations = set()
sha = re.compile(r"^[0-9a-f]{64}$")
for plugin in plugins:
    if not isinstance(plugin, dict):
        errors.append("plugin entries must be objects")
        continue
    identifier = str(plugin.get("identifier") or "")
    if identifier in seen:
        errors.append(f"duplicate identifier {identifier!r}")
    seen.add(identifier)
    for key in ("name", "repo", "tag", "version", "asset", "dest"):
        if not str(plugin.get(key) or "").strip():
            errors.append(f"{identifier}.{key} must be present")
    identity = expected.get(identifier)
    if identity and plugin.get("repo") != identity[1]:
        errors.append(f"{identifier}.repo must match its official repository")
    asset = str(plugin.get("asset") or "")
    if Path(asset).name != asset or not asset.endswith(".iinaplgz"):
        errors.append(f"{identifier}.asset must be a basename ending in .iinaplgz")
    if identity and asset != f"{identity[2]}-{plugin.get('version')}.iinaplgz":
        errors.append(f"{identifier}.asset must match its official package/version")
    if plugin.get("tag") != f"v{plugin.get('version')}":
        errors.append(f"{identifier}.tag must match its version")
    destination = str(plugin.get("dest") or "")
    if destination in seen_destinations:
        errors.append(f"duplicate destination {destination!r}")
    seen_destinations.add(destination)
    if Path(destination).name != destination or destination != (identity[0] if identity else None):
        errors.append(f"{identifier}.dest must be the exact pinned bundle name")
    if not sha.fullmatch(str(plugin.get("sha256") or "")):
        errors.append(f"{identifier}.sha256 must be a lowercase SHA-256")
if seen != set(expected):
    errors.append("identifiers must be exactly the three pinned official plugins")
if errors:
    print("; ".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
}

pin_rows() {
  UV_NO_PROJECT=1 uv run --offline --no-project python -I - "$PIN" <<'PY'
import json
import sys
for plugin in json.load(open(sys.argv[1]))["plugins"]:
    print(plugin["identifier"], plugin["name"], plugin["repo"], plugin["tag"], plugin["version"], plugin["asset"], plugin["sha256"], plugin["dest"], sep="\t")
PY
}

file_sha256() {
  shasum -a 256 "$1" | cut -d ' ' -f 1
}

github_release_url() {
  printf 'https://github.com/%s/releases/download/%s/%s\n' "$1" "$2" "$3"
}

plugin_version() {
  local folder="$1"
  UV_NO_PROJECT=1 uv run --offline --no-project python -I - "$folder" <<'PY'
import json
import sys
from pathlib import Path

folder = Path(sys.argv[1])
for name in ("Info.json", "package.json"):
    try:
        data = json.loads((folder / name).read_text())
    except (OSError, ValueError):
        continue
    if isinstance(data, dict) and isinstance(data.get("version"), str):
        print(data["version"])
        break
PY
}

validate_installed_identity() {
  local folder="$1" identifier="$2" version="$3"
  UV_NO_PROJECT=1 uv run --offline --no-project python -I - "$folder" "$identifier" "$version" <<'PY'
import json
import sys
from pathlib import Path

folder, identifier, version = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
try:
    info = json.loads((folder / "Info.json").read_text())
    package = json.loads((folder / "package.json").read_text()) if (folder / "package.json").is_file() else None
except (OSError, ValueError) as exc:
    raise SystemExit(f"invalid plugin metadata: {exc}")
if isinstance(info, dict):
    if info.get("identifier") != identifier or info.get("version") != version:
        raise SystemExit("plugin manifest identifier/version mismatch")
elif isinstance(info, list):
    if not all(isinstance(permission, str) for permission in info):
        raise SystemExit("plugin permission list is invalid")
    if not isinstance(package, dict) or package.get("version") != version:
        raise SystemExit("plugin package version mismatch")
    expected_names = {
        "io.iina.ytdl": "iina-plugin-ytdl",
        "io.iina.opensub": "iina-plugin-opensub",
        "io.iina.user-script": "iina-plugin-user-scripts",
    }
    if package.get("name") != expected_names.get(identifier):
        raise SystemExit("plugin package name does not match identifier")
else:
    raise SystemExit("plugin Info.json must be an object or permission list")
PY
}

print_preview() {
  local id name repo tag version asset sha dest live
  printf 'iina-plugins: pin=%s\n' "$PIN"
  printf 'iina-plugins: dest=%s\n' "$PLUGIN_ROOT"
  while IFS=$'\t' read -r id name repo tag version asset sha dest; do
    live="$(plugin_version "$PLUGIN_ROOT/$dest")"
    [[ -n "$live" ]] || live="absent"
    printf 'iina-plugins: %-18s id=%s repo=%s@%s pin=%s live=%s asset=%s sha256=%s\n' "$name" "$id" "$repo" "$tag" "$version" "$live" "$asset" "$sha"
  done < <(pin_rows)
}

archive_paths_safe() {
  local archive="$1"
  UV_NO_PROJECT=1 uv run --offline --no-project python -I - "$archive" <<'PY'
import sys
from pathlib import Path, PurePosixPath
from zipfile import ZipFile

import re
import stat

path_on_disk = Path(sys.argv[1])
if path_on_disk.stat().st_size > 64 * 1024 * 1024:
    raise SystemExit('oversized plugin archive')
seen = set()
total = 0
with ZipFile(path_on_disk) as archive:
    members = archive.infolist()
    if len(members) > 4096:
        raise SystemExit('too many plugin archive members')
    for info in members:
        total += info.file_size
        if info.file_size > 64 * 1024 * 1024 or total > 256 * 1024 * 1024:
            raise SystemExit(f'oversized plugin archive entry: {info.filename!r}')
        # ZIP hardlink metadata is nonstandard; allow only ZIP64, timestamps, and uid/gid.
        extra = info.extra
        offset = 0
        while offset < len(extra):
            if len(extra) - offset < 4:
                raise SystemExit(f'unsafe archive extra field: {info.filename!r}')
            field_id = int.from_bytes(extra[offset:offset + 2], 'little')
            size = int.from_bytes(extra[offset + 2:offset + 4], 'little')
            offset += 4 + size
            if offset > len(extra) or field_id not in (0x0001, 0x5455, 0x7875):
                raise SystemExit(f'unsafe archive extra field: {info.filename!r}')
        name = info.filename
        path = PurePosixPath(name)
        kind = stat.S_IFMT(info.external_attr >> 16)
        if (not name or "\\" in name or "\x00" in name or name.startswith("/")
                or re.match(r"^[A-Za-z]:", name) or any(part in (".", "..") for part in name.split("/"))
                or info.flag_bits & 0x1 or kind not in (0, stat.S_IFREG, stat.S_IFDIR)
                or (info.is_dir() != (kind == stat.S_IFDIR) and kind != 0)):
            print(f"unsafe archive entry: {name!r}", file=sys.stderr)
            raise SystemExit(1)
        normalized = str(path).rstrip("/").casefold()
        if normalized in seen:
            print(f"duplicate archive entry: {name!r}", file=sys.stderr)
            raise SystemExit(1)
        seen.add(normalized)
PY
}

stage_plugin() {
  local id="$1" repo="$2" tag="$3" version="$4" asset="$5" wanted="$6" dest="$7" root="$8"
  local archive_dir archive stage="$root/stage/$dest" url got
  archive_dir="$(mktemp -d "$root/archive.XXXXXX")"
  archive="$archive_dir/$asset"
  url="$(github_release_url "$repo" "$tag" "$asset")"
  printf 'iina-plugins: download %s %s@%s\n' "$asset" "$repo" "$tag"
  curl --fail --location --retry 3 --silent --show-error "$url" --output "$archive"
  got="$(file_sha256 "$archive")"
  [[ "$got" == "$wanted" ]] || die "SHA-256 mismatch for $asset (got $got, wanted $wanted)"
  archive_paths_safe "$archive" || die "unsafe archive: $asset"
  mkdir -p "$stage"
  unzip -q "$archive" -d "$stage"
  [[ -f "$stage/Info.json" ]] || die "$asset has no root Info.json"
  validate_installed_identity "$stage" "$id" "$version" || die "$asset metadata does not match $id@$version"
}

cmd_preview() {
  command -v uv >/dev/null 2>&1 || die "required tool unavailable: uv"
  validate_pin
  print_preview
  printf 'iina-plugins: ok (preview)\n'
}

recover_install() {
  local code="$1" id name repo tag version asset sha dest live replacement failed=0
  trap - ERR
  trap '' INT TERM
  if [[ "$INSTALL_ACTIVE" -eq 1 && -n "$BACKUP" ]]; then
    while IFS=$'\t' read -r id name repo tag version asset sha dest; do
      live="$PLUGIN_ROOT/$dest"
      replacement="$BACKUP/replacing-$dest"
      if [[ -d "$replacement" ]]; then
        /bin/rm -rf -- "$live"
        /bin/mv "$replacement" "$live" || failed=1
      elif [[ -d "$BACKUP/$dest" ]]; then
        /bin/rm -rf -- "$live"
        /bin/cp -R -p "$BACKUP/$dest" "$live" || failed=1
      elif [[ -f "$BACKUP/absent.txt" ]] && grep -qxF -- "$dest" "$BACKUP/absent.txt"; then
        /bin/rm -rf -- "$live"
      else
        failed=1
      fi
    done <"$BACKUP/targets.tsv"
    if [[ "$failed" -eq 0 ]] && UV_NO_PROJECT=1 uv run --offline --no-project python -I "$ROOT/checks/iina-backup-integrity.py" verify plugins "$BACKUP"; then
      /bin/rm -f -- "$BACKUP/dirty"
      printf 'iina-plugins: interrupted install recovered; backup=%s\n' "$BACKUP" >&2
    else
      printf 'iina-plugins: recovery incomplete; inspect %s before retrying\n' "$BACKUP" >&2
    fi
  fi
  exit "$code"
}

cmd_install() {
  local id name repo tag version asset sha dest work live target
  for tool in uv curl shasum unzip; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool unavailable: $tool"
  done
  validate_pin
  print_preview
  if [[ "$APPLY" -eq 0 ]]; then
    printf 'iina-plugins: dry-run; use install --apply to download and install\n'
    return 0
  fi
  acquire_operation_lock
  if pgrep -x IINA >/dev/null 2>&1; then
    die "IINA is running; quit it before installing plugins"
  fi
  mkdir -p "$STATE_ROOT" "$PLUGIN_ROOT"
  work="$(mktemp -d "$STATE_ROOT/download.XXXXXX")"
  WORK_DIR="$work"
  trap cleanup EXIT
  mkdir -p "$work/stage"
  while IFS=$'\t' read -r id name repo tag version asset sha dest; do
    stage_plugin "$id" "$repo" "$tag" "$version" "$asset" "$sha" "$dest" "$work"
  done < <(pin_rows)

  BACKUP="$(mktemp -d "$STATE_ROOT/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")"
  pin_rows >"$BACKUP/targets.tsv"
  while IFS=$'\t' read -r id name repo tag version asset sha dest; do
    live="$PLUGIN_ROOT/$dest"
    [[ ! -L "$live" ]] || die "refuse symlinked plugin target: $live"
    if [[ -d "$live" ]]; then
      cp -R -p "$live" "$BACKUP/$dest"
    else
      printf '%s\n' "$dest" >>"$BACKUP/absent.txt"
    fi
  done <"$BACKUP/targets.tsv"
  UV_NO_PROJECT=1 uv run --offline --no-project python -I "$ROOT/checks/iina-backup-integrity.py" create plugins "$BACKUP"
  UV_NO_PROJECT=1 uv run --offline --no-project python -I "$ROOT/checks/iina-backup-integrity.py" verify plugins "$BACKUP"
  if pgrep -x IINA >/dev/null 2>&1; then die 'IINA started during staging; quit it before installing plugins'; fi
  printf 'ready\n' >"$BACKUP/complete"
  INSTALL_ACTIVE=1
  printf 'install-in-progress\n' >"$BACKUP/dirty"
  trap 'recover_install "$?"' ERR
  trap 'recover_install 130' INT
  trap 'recover_install 143' TERM
  while IFS=$'\t' read -r id name repo tag version asset sha dest; do
    live="$PLUGIN_ROOT/$dest"
    target="$work/stage/$dest"
    if [[ -d "$live" ]]; then
      mv "$live" "$BACKUP/replacing-$dest"
    fi
    mv "$target" "$live"
    printf 'iina-plugins: installed %s %s\n' "$id" "$version"
  done <"$BACKUP/targets.tsv"
  cmd_doctor
  /bin/rm -f -- "$BACKUP/dirty"
  trap - ERR INT TERM
  INSTALL_ACTIVE=0
  printf 'iina-plugins: backup=%s\n' "$BACKUP"
}

cmd_doctor() {
  command -v uv >/dev/null 2>&1 || die "required tool unavailable: uv"
  validate_pin
  local id name repo tag version asset sha dest live failed=0
  while IFS=$'\t' read -r id name repo tag version asset sha dest; do
    live="$(plugin_version "$PLUGIN_ROOT/$dest")"
    if [[ "$live" != "$version" ]] || ! validate_installed_identity "$PLUGIN_ROOT/$dest" "$id" "$version" >/dev/null 2>&1; then
      printf 'iina-plugins: drift %s live=%s pinned=%s\n' "$id" "${live:-absent}" "$version" >&2
      failed=1
    fi
  done < <(pin_rows)
  [[ "$failed" -eq 0 ]] || die "doctor failed"
  printf 'iina-plugins: ok (all official plugins match pin)\n'
}

latest_backup() {
  local candidate
  while IFS= read -r candidate; do
    [[ -f "$candidate/complete" && "$(<"$candidate/complete")" == ready && -f "$candidate/targets.tsv" && ! -e "$candidate/dirty" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done < <(find "$STATE_ROOT" -mindepth 1 -maxdepth 1 -type d \
    ! -name 'download.*' ! -name 'pre-restore-*' | LC_ALL=C sort -r)
}

recover_restore() {
  local code="$1" id name repo tag version asset sha dest live failed=0
  trap - ERR
  trap '' INT TERM
  if [[ "$RESTORE_ACTIVE" -eq 1 && -n "$RESCUE" ]]; then
    if ! UV_NO_PROJECT=1 uv run --offline --no-project python -I "$ROOT/checks/iina-backup-integrity.py" verify plugins "$RESCUE"; then
      printf 'iina-plugins: rescue corrupted; inspect %s before recovery\n' "$RESCUE" >&2
      exit "$code"
    fi
    while IFS=$'\t' read -r id name repo tag version asset sha dest; do
      live="$PLUGIN_ROOT/$dest"
      if [[ -d "$RESCUE/$dest" ]]; then
        /bin/rm -rf -- "$live" || failed=1
        if ! /bin/cp -R -p "$RESCUE/$dest" "$live"; then failed=1; fi
      elif [[ -f "$RESCUE/absent.txt" ]] && grep -qxF -- "$dest" "$RESCUE/absent.txt"; then
        /bin/rm -rf -- "$live" || failed=1
      else
        failed=1
      fi
    done <"$RESCUE/targets.tsv"
    if [[ "$failed" -eq 0 ]]; then
      /bin/rm -f -- "$RESCUE/dirty"
      printf 'iina-plugins: interrupted restore recovered; rescue=%s\n' "$RESCUE" >&2
    else
      printf 'iina-plugins: recovery incomplete; inspect rescue=%s\n' "$RESCUE" >&2
    fi
  fi
  exit "$code"
}

cmd_restore() {
  command -v uv >/dev/null 2>&1 || die "required tool unavailable: uv"
  local backup id name repo tag version asset sha dest live rescue targets
  backup="$(latest_backup || true)"
  [[ -n "$backup" ]] || die "no backups under $STATE_ROOT"
  targets="$backup/targets.tsv"
  [[ -f "$targets" && ! -L "$targets" ]] || die "backup lacks immutable target list: $backup"
  [[ ! -e "$backup/dirty" ]] || die "backup has dirty marker: $backup"
  [[ -f "$backup/complete" && "$(<"$backup/complete")" == ready ]] || die "backup is incomplete: $backup"
  UV_NO_PROJECT=1 uv run --offline --no-project python -I - "$targets" <<'PY' || die "backup target list is incomplete or invalid"
import sys
from pathlib import Path

expected = {
    ("io.iina.ytdl", "io.iina.ytdl.iinaplugin"),
    ("io.iina.opensub", "io.iina.opensub.iinaplugin"),
    ("io.iina.user-script", "io.iina.user-script.iinaplugin"),
}
rows = [line.split("\t") for line in Path(sys.argv[1]).read_text().splitlines()]
if len(rows) != len(expected) or any(len(row) != 8 for row in rows):
    raise SystemExit(1)
if {(row[0], row[7]) for row in rows} != expected:
    raise SystemExit(1)
PY
  # The snapshot's own allowlisted targets, not a later-edited pin, own rollback.
  while IFS=$'\t' read -r id name repo tag version asset sha dest; do
    case "$id:$dest" in
      io.iina.ytdl:io.iina.ytdl.iinaplugin | io.iina.opensub:io.iina.opensub.iinaplugin | io.iina.user-script:io.iina.user-script.iinaplugin) ;;
      *) die "unsafe backup target $id:$dest" ;;
    esac
    live="$PLUGIN_ROOT/$dest"
    [[ ! -L "$live" ]] || die "refuse symlinked plugin target: $live"
    if [[ -d "$backup/$dest" ]]; then
      [[ ! -L "$backup/$dest" ]] || die "refuse symlinked plugin backup: $dest"
    elif [[ ! -f "$backup/absent.txt" ]] || ! grep -qxF -- "$dest" "$backup/absent.txt"; then
      die "backup does not cover $dest"
    fi
  done <"$targets"
  UV_NO_PROJECT=1 uv run --offline --no-project python -I "$ROOT/checks/iina-backup-integrity.py" verify plugins "$backup" || die "backup content verification failed: $backup"
  printf 'iina-plugins: restore from %s apply=%s\n' "$backup" "$APPLY"
  if [[ "$APPLY" -eq 0 ]]; then
    printf 'iina-plugins: dry-run; use restore --apply to mutate\n'
    return 0
  fi
  acquire_operation_lock
  if pgrep -x IINA >/dev/null 2>&1; then
    die "IINA is running; quit it before restoring plugins"
  fi
  rescue="$(mktemp -d "$STATE_ROOT/pre-restore-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")"
  local staged="$rescue/staged"
  mkdir -p "$staged"
  /bin/cp -p "$targets" "$rescue/targets.tsv"
  while IFS=$'\t' read -r id name repo tag version asset sha dest; do
    if [[ -d "$backup/$dest" ]]; then
      /bin/cp -R -p "$backup/$dest" "$staged/$dest"
    fi
    live="$PLUGIN_ROOT/$dest"
    if [[ -d "$live" ]]; then
      /bin/cp -R -p "$live" "$rescue/$dest"
    else
      printf '%s\n' "$dest" >>"$rescue/absent.txt"
    fi
  done <"$targets"
  UV_NO_PROJECT=1 uv run --offline --no-project python -I "$ROOT/checks/iina-backup-integrity.py" create plugins "$rescue"
  UV_NO_PROJECT=1 uv run --offline --no-project python -I "$ROOT/checks/iina-backup-integrity.py" verify plugins "$rescue"
  if pgrep -x IINA >/dev/null 2>&1; then die 'IINA started during restore staging; quit it before restoring plugins'; fi
  RESCUE="$rescue"
  RESTORE_ACTIVE=1
  printf 'restore-in-progress\n' >"$rescue/dirty"
  trap 'recover_restore "$?"' ERR
  trap 'recover_restore 130' INT
  trap 'recover_restore 143' TERM
  while IFS=$'\t' read -r id name repo tag version asset sha dest; do
    live="$PLUGIN_ROOT/$dest"
    if [[ -d "$live" ]]; then
      mv "$live" "$rescue/replacing-$dest"
    fi
    if [[ -d "$staged/$dest" ]]; then
      mv "$staged/$dest" "$live"
    fi
  done <"$targets"
  /bin/rm -f -- "$rescue/dirty"
  trap - ERR INT TERM
  RESTORE_ACTIVE=0
  printf 'iina-plugins: rescue=%s\n' "$rescue"
  printf 'iina-plugins: restored official plugins\n'
}

case "$CMD" in
  preview) cmd_preview ;;
  install) cmd_install ;;
  doctor) cmd_doctor ;;
  restore) cmd_restore ;;
  *) die "unknown subcommand $CMD" ;;
esac
