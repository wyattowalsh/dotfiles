#!/usr/bin/env bash
# Pinned IINA/mpv shader installer. Downloads GPL assets; never vendors them.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" # Never execute from a downloaded archive or a caller-controlled directory.
PIN="${IINA_SHADERS_PIN:-$ROOT/rig/home/private_dot_config/iina-mpv/shaders-pin.json}"
DEST_ROOT="${IINA_SHADERS_DEST_ROOT:-$HOME/.config/iina-mpv}"
DEST="$DEST_ROOT/shaders"
STATE_ROOT="${IINA_SHADERS_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/iina-shaders}"
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
Usage: checks/iina-shaders.sh [preview|install|doctor|restore] [--apply|--dry-run]

preview   Validate and show pinned GitHub sources (default; no network)
install   Download, verify, and atomically replace the live shader set
           (requires --apply to mutate)
doctor    Verify every installed shader against the pin
restore   Restore the latest pre-install shader set (requires --apply)

The installed shader assets are GPL-3.0 and remain untracked. Only their
source/tag/file SHA-256 manifest is committed to this repository.
EOF
}

die() {
  printf 'iina-shaders: %s\n' "$*" >&2
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

require_tools() {
  local tool
  for tool in uv shasum; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool unavailable: $tool"
  done
}

validate_pin() {
  [[ -f "$PIN" ]] || die "missing pin: $PIN"
  UV_NO_PROJECT=1 uv run --offline --no-project python -I - "$PIN" <<'PY' || die "invalid shader pin"
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
if data.get("dest") != ".config/iina-mpv/shaders":
    errors.append("dest must be .config/iina-mpv/shaders")
sources = data.get("sources")
if not isinstance(sources, list):
    errors.append("sources must be a list")
    sources = []
ids = [source.get("id") for source in sources if isinstance(source, dict)]
if len(sources) != 2 or sorted(ids) != ["anime4k", "fsrcnnx"]:
    errors.append("sources must contain exactly one anime4k and one fsrcnnx object")
sha = re.compile(r"^[0-9a-f]{64}$")
for source in sources:
    if not isinstance(source, dict):
        errors.append("source entries must be objects")
        continue
    for key in ("repo", "tag"):
        if not str(source.get(key) or "").strip():
            errors.append(f"{source.get('id')}.{key} must be present")
    if source.get("id") == "anime4k":
        asset = str(source.get("asset") or "")
        if not asset or Path(asset).name != asset or not asset.endswith(".zip"):
            errors.append("anime4k.asset must be a ZIP basename")
        if not sha.fullmatch(str(source.get("sha256") or "")):
            errors.append("anime4k.sha256 must be a lowercase SHA-256")
        entries = source.get("files")
    else:
        entries = source.get("assets")
    if not isinstance(entries, list) or not entries:
        errors.append(f"{source.get('id')} file list must be non-empty")
        continue
    names = set()
    for entry in entries:
        name = str(entry.get("name") or "") if isinstance(entry, dict) else ""
        digest = str(entry.get("sha256") or "") if isinstance(entry, dict) else ""
        if not name or Path(name).name != name or name in names or not name.endswith(".glsl"):
            errors.append(f"invalid or duplicate shader filename: {name!r}")
        names.add(name)
        if not sha.fullmatch(digest):
            errors.append(f"invalid SHA-256 for {name!r}")
if errors:
    print("; ".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
}

pin_rows() {
  UV_NO_PROJECT=1 uv run --offline --no-project python -I - "$PIN" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
for source in data["sources"]:
    if source["id"] == "anime4k":
        print("source", source["id"], source["repo"], source["tag"], source["asset"], source["sha256"], sep="\t")
        for entry in source["files"]:
            print("file", source["id"], entry["name"], entry["sha256"], sep="\t")
    else:
        for entry in source["assets"]:
            print("asset", source["id"], source["repo"], source["tag"], entry["name"], entry["sha256"], sep="\t")
PY
}

file_sha256() {
  shasum -a 256 "$1" | cut -d ' ' -f 1
}

verify_hash() {
  local path="$1"
  local wanted="$2"
  local got
  [[ -f "$path" ]] || die "missing file for verification: $path"
  got="$(file_sha256 "$path")"
  [[ "$got" == "$wanted" ]] || die "SHA-256 mismatch for $path (got $got, wanted $wanted)"
}

github_release_url() {
  local repo="$1"
  local tag="$2"
  local asset="$3"
  printf 'https://github.com/%s/releases/download/%s/%s\n' "$repo" "$tag" "$asset"
}

print_preview() {
  local kind a b c d e
  printf 'iina-shaders: pin=%s\n' "$PIN"
  printf 'iina-shaders: dest=%s (%s)\n' "$DEST" "$([[ -d "$DEST" ]] && printf present || printf absent)"
  while IFS=$'\t' read -r kind a b c d e; do
    case "$kind" in
      source) printf 'iina-shaders: source=%s repo=%s tag=%s asset=%s sha256=%s\n' "$a" "$b" "$c" "$d" "$e" ;;
      asset) printf 'iina-shaders: source=%s repo=%s tag=%s asset=%s sha256=%s\n' "$a" "$b" "$c" "$d" "$e" ;;
      file) printf 'iina-shaders: file=%s/%s sha256=%s\n' "$a" "$b" "$c" ;;
    esac
  done < <(pin_rows)
}

stage_downloads() {
  local stage="$1"
  local downloads="$2"
  local anime_repo="" anime_tag="" anime_asset="" anime_sha=""
  local kind a b c d e url archive archive_dir
  mkdir -p "$stage" "$downloads"
  while IFS=$'\t' read -r kind a b c d e; do
    case "$kind" in
      source)
        anime_repo="$b"
        anime_tag="$c"
        anime_asset="$d"
        anime_sha="$e"
        ;;
      asset)
        url="$(github_release_url "$b" "$c" "$d")"
        printf 'iina-shaders: download %s %s@%s\n' "$d" "$b" "$c"
        curl --fail --location --retry 3 --silent --show-error "$url" --output "$downloads/$d"
        verify_hash "$downloads/$d" "$e"
        cp -p "$downloads/$d" "$stage/$d"
        ;;
    esac
  done < <(pin_rows)

  [[ -n "$anime_repo" && -n "$anime_asset" ]] || die "anime4k source missing from pin"
  url="$(github_release_url "$anime_repo" "$anime_tag" "$anime_asset")"
  archive_dir="$(mktemp -d "$WORK_DIR/archive.XXXXXX")"
  archive="$archive_dir/$anime_asset"
  printf 'iina-shaders: download %s %s@%s\n' "$anime_asset" "$anime_repo" "$anime_tag"
  curl --fail --location --retry 3 --silent --show-error "$url" --output "$archive"
  verify_hash "$archive" "$anime_sha"
  # Read only uniquely named pinned files; never unzip arbitrary archive members.
  mkdir -p "$stage"
  UV_NO_PROJECT=1 uv run --offline --no-project python -I - "$archive" "$stage" "$PIN" <<'PY' || die "unsafe Anime4K archive"
import json
import re
import shutil
import stat
import sys
from pathlib import Path, PurePosixPath
from zipfile import ZipFile

archive_path, stage_path, pin_path = map(Path, sys.argv[1:])
if archive_path.stat().st_size > 64 * 1024 * 1024:
    raise SystemExit('oversized shader archive')
pin = json.loads(pin_path.read_text())
wanted = {file["name"] for source in pin["sources"] if source["id"] == "anime4k" for file in source["files"]}
found = {}
seen = set()
with ZipFile(archive_path) as archive:
    members = archive.infolist()
    if len(members) > 4096:
        raise SystemExit('too many shader archive members')
    total = 0
    for info in members:
        total += info.file_size
        if info.file_size > 256 * 1024 * 1024 or total > 1024 * 1024 * 1024:
            raise SystemExit(f'oversized shader archive entry: {info.filename!r}')
        # Reject unsupported ZIP metadata, including nonstandard hardlink fields.
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
        parts = path.parts
        mode = info.external_attr >> 16
        kind = stat.S_IFMT(mode)
        if (not name or "\\" in name or "\x00" in name or name.startswith("/")
                or re.match(r"^[A-Za-z]:", name) or any(part in (".", "..") for part in name.split("/"))
                or not parts or info.flag_bits & 0x1 or kind not in (0, stat.S_IFREG, stat.S_IFDIR)
                or (info.is_dir() != (kind == stat.S_IFDIR) and kind != 0)):
            raise SystemExit(f"unsafe archive entry: {name!r}")
        normalized = str(path).rstrip("/").casefold()
        if normalized in seen:
            raise SystemExit(f"duplicate archive entry: {name!r}")
        seen.add(normalized)
        if info.is_dir() or path.name not in wanted:
            continue
        if info.file_size > 16 * 1024 * 1024 or path.name in found:
            raise SystemExit(f"ambiguous or oversized shader: {path.name}")
        found[path.name] = info
    if set(found) != wanted:
        raise SystemExit(f"missing or ambiguous shaders: {sorted(wanted - set(found))}")
    for name, info in found.items():
        with archive.open(info) as source, (stage_path / name).open("xb") as target:
            shutil.copyfileobj(source, target)
PY
  while IFS=$'\t' read -r kind a b c _; do
    [[ "$kind" == "file" && "$a" == "anime4k" ]] || continue
    verify_hash "$stage/$b" "$c"
  done < <(pin_rows)
}

cmd_preview() {
  require_tools
  validate_pin
  print_preview
  printf 'iina-shaders: ok (preview)\n'
}

recover_install() {
  local code="$1" failed=0
  trap - ERR
  trap '' INT TERM
  if [[ "$INSTALL_ACTIVE" -eq 1 && -n "$BACKUP" ]]; then
    if [[ -d "$BACKUP/shaders" ]]; then
      /bin/rm -rf -- "$DEST"
      /bin/cp -R -p "$BACKUP/shaders" "$DEST" || failed=1
    elif [[ -f "$BACKUP/absent" ]]; then
      /bin/rm -rf -- "$DEST"
    else
      failed=1
    fi
    if [[ "$failed" -eq 0 ]] && UV_NO_PROJECT=1 uv run --offline --no-project python -I "$ROOT/checks/iina-backup-integrity.py" verify shaders "$BACKUP"; then
      /bin/rm -f -- "$BACKUP/dirty"
      printf 'iina-shaders: interrupted install recovered; backup=%s\n' "$BACKUP" >&2
    else
      printf 'iina-shaders: recovery incomplete; inspect %s before retrying\n' "$BACKUP" >&2
    fi
  fi
  exit "$code"
}

cmd_install() {
  require_tools
  validate_pin
  print_preview
  if [[ "$APPLY" -eq 0 ]]; then
    printf 'iina-shaders: dry-run; use install --apply to download and install\n'
    return 0
  fi
  acquire_operation_lock
  if pgrep -x IINA >/dev/null 2>&1; then die 'quit IINA before installing shaders'; fi
  command -v curl >/dev/null 2>&1 || die "required tool unavailable: curl"
  mkdir -p "$STATE_ROOT" "$DEST_ROOT"
  local work stage backup
  work="$(mktemp -d "$STATE_ROOT/download.XXXXXX")"
  WORK_DIR="$work"
  trap cleanup EXIT
  stage="$work/shaders"
  stage_downloads "$stage" "$work/assets"

  BACKUP="$(mktemp -d "$STATE_ROOT/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")"
  if [[ -d "$DEST" ]]; then
    cp -R -p "$DEST" "$BACKUP/shaders"
    printf 'iina-shaders: backup %s\n' "$BACKUP/shaders"
  else
    : >"$BACKUP/absent"
  fi
  UV_NO_PROJECT=1 uv run --offline --no-project python -I "$ROOT/checks/iina-backup-integrity.py" create shaders "$BACKUP"
  UV_NO_PROJECT=1 uv run --offline --no-project python -I "$ROOT/checks/iina-backup-integrity.py" verify shaders "$BACKUP"
  if pgrep -x IINA >/dev/null 2>&1; then die 'IINA started during staging; quit it before installing shaders'; fi
  printf 'ready\n' >"$BACKUP/complete"
  INSTALL_ACTIVE=1
  printf 'install-in-progress\n' >"$BACKUP/dirty"
  trap 'recover_install "$?"' ERR
  trap 'recover_install 130' INT
  trap 'recover_install 143' TERM
  if [[ -d "$DEST" ]]; then mv "$DEST" "$BACKUP/replacing-shaders"; fi
  mv "$stage" "$DEST"
  printf 'iina-shaders: installed %s shaders at %s\n' "$(find "$DEST" -type f -name '*.glsl' | wc -l | tr -d ' ')" "$DEST"
  cmd_doctor
  /bin/rm -f -- "$BACKUP/dirty"
  trap - ERR INT TERM
  INSTALL_ACTIVE=0
}

cmd_doctor() {
  require_tools
  validate_pin
  [[ -d "$DEST" ]] || die "shader directory missing: $DEST"
  local kind source name wanted path failed=0 count=0 a b c d e
  while IFS=$'\t' read -r kind a b c d e; do
    case "$kind" in
      file)
        source="$a"
        name="$b"
        wanted="$c"
        ;;
      asset)
        source="$a"
        name="$d"
        wanted="$e"
        ;;
      *) continue ;;
    esac
    path="$DEST/$name"
    count=$((count + 1))
    if [[ ! -f "$path" ]]; then
      printf 'iina-shaders: missing %s/%s\n' "$source" "$name" >&2
      failed=1
    elif [[ "$(file_sha256 "$path")" != "$wanted" ]]; then
      printf 'iina-shaders: drift %s/%s\n' "$source" "$name" >&2
      failed=1
    fi
  done < <(pin_rows)
  [[ "$failed" -eq 0 ]] || die "doctor failed"
  printf 'iina-shaders: ok (%s pinned shaders)\n' "$count"
}

latest_backup() {
  local candidate
  while IFS= read -r candidate; do
    [[ -f "$candidate/complete" && "$(<"$candidate/complete")" == ready && ! -e "$candidate/dirty" ]] || continue
    if [[ -d "$candidate/shaders" || -f "$candidate/absent" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(find "$STATE_ROOT" -mindepth 1 -maxdepth 1 -type d \
    ! -name 'download.*' ! -name 'pre-restore-*' | LC_ALL=C sort -r)
}

recover_restore() {
  local code="$1" failed=0
  trap - ERR
  trap '' INT TERM
  if [[ "$RESTORE_ACTIVE" -eq 1 && -n "$RESCUE" ]]; then
    if ! UV_NO_PROJECT=1 uv run --offline --no-project python -I "$ROOT/checks/iina-backup-integrity.py" verify shaders "$RESCUE"; then
      printf 'iina-shaders: rescue corrupted; inspect %s before recovery\n' "$RESCUE" >&2
      exit "$code"
    fi
    if [[ -d "$RESCUE/shaders" ]]; then
      /bin/rm -rf -- "$DEST" || failed=1
      if ! /bin/cp -R -p "$RESCUE/shaders" "$DEST"; then
        failed=1
      fi
    elif [[ -f "$RESCUE/absent" ]]; then
      /bin/rm -rf -- "$DEST" || failed=1
    else
      failed=1
    fi
    if [[ "$failed" -eq 0 ]]; then
      /bin/rm -f -- "$RESCUE/dirty"
      printf 'iina-shaders: interrupted restore recovered; rescue=%s\n' "$RESCUE" >&2
    else
      printf 'iina-shaders: recovery incomplete; inspect rescue=%s\n' "$RESCUE" >&2
    fi
  fi
  exit "$code"
}

cmd_restore() {
  require_tools
  local backup
  backup="$(latest_backup || true)"
  [[ -n "$backup" ]] || die "no complete backups under $STATE_ROOT"
  [[ ! -L "$backup" && -f "$backup/complete" ]] || die "unsafe shader backup: $backup"
  [[ ! -e "$backup/dirty" ]] || die "shader backup has dirty marker: $backup"
  if [[ -d "$backup/shaders" ]]; then
    [[ ! -L "$backup/shaders" ]] || die "symlinked shader backup: $backup"
  elif [[ ! -f "$backup/absent" || -L "$backup/absent" ]]; then
    die "backup is incomplete: $backup"
  fi
  [[ ! -L "$DEST" ]] || die "symlinked shader destination: $DEST"
  UV_NO_PROJECT=1 uv run --offline --no-project python -I "$ROOT/checks/iina-backup-integrity.py" verify shaders "$backup" || die "backup content verification failed: $backup"
  printf 'iina-shaders: restore from %s apply=%s\n' "$backup" "$APPLY"
  if [[ "$APPLY" -eq 0 ]]; then
    printf 'iina-shaders: dry-run; use restore --apply to mutate\n'
    return 0
  fi
  acquire_operation_lock
  if pgrep -x IINA >/dev/null 2>&1; then die 'quit IINA before restoring shaders'; fi
  local rescue staged=""
  rescue="$(mktemp -d "$STATE_ROOT/pre-restore-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")"
  if [[ -d "$backup/shaders" ]]; then
    staged="$rescue/staged-shaders"
    cp -R -p "$backup/shaders" "$staged"
  elif [[ ! -f "$backup/absent" ]]; then
    die "backup is incomplete: $backup"
  fi
  [[ ! -L "$DEST" ]] || die "symlinked shader destination: $DEST"
  if [[ -d "$DEST" ]]; then
    /bin/cp -R -p "$DEST" "$rescue/shaders"
  else
    : >"$rescue/absent"
  fi
  UV_NO_PROJECT=1 uv run --offline --no-project python -I "$ROOT/checks/iina-backup-integrity.py" create shaders "$rescue"
  UV_NO_PROJECT=1 uv run --offline --no-project python -I "$ROOT/checks/iina-backup-integrity.py" verify shaders "$rescue"
  if pgrep -x IINA >/dev/null 2>&1; then die 'IINA started during restore staging; quit it before restoring shaders'; fi
  RESCUE="$rescue"
  RESTORE_ACTIVE=1
  printf 'restore-in-progress\n' >"$rescue/dirty"
  trap 'recover_restore "$?"' ERR
  trap 'recover_restore 130' INT
  trap 'recover_restore 143' TERM
  if [[ -d "$DEST" ]]; then
    mv "$DEST" "$rescue/replacing-shaders"
    printf 'iina-shaders: rescue %s\n' "$rescue/shaders"
  fi
  if [[ -n "$staged" ]]; then
    mv "$staged" "$DEST"
    printf 'iina-shaders: restored %s\n' "$DEST"
  else
    printf 'iina-shaders: restored absent state\n'
  fi
  /bin/rm -f -- "$rescue/dirty"
  trap - ERR INT TERM
  RESTORE_ACTIVE=0
}

case "$CMD" in
  preview) cmd_preview ;;
  install) cmd_install ;;
  doctor) cmd_doctor ;;
  restore) cmd_restore ;;
  *) die "unknown subcommand $CMD" ;;
esac
