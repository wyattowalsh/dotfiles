#!/usr/bin/env -S uv run python
"""Record and verify exact local IINA installer backups without following links."""

import hashlib
import json
import sys
from pathlib import Path

PLUGIN_TARGETS = (
    "io.iina.ytdl.iinaplugin",
    "io.iina.opensub.iinaplugin",
    "io.iina.user-script.iinaplugin",
)


def fail(reason: str) -> None:
    raise SystemExit(f"iina-backup-integrity: {reason}")


def describe(root: Path, kind: str) -> dict:
    names = PLUGIN_TARGETS if kind == "plugins" else ("shaders",)
    absent_name = "absent.txt" if kind == "plugins" else "absent"
    absent = root / absent_name
    if absent.is_symlink() or (absent.exists() and not absent.is_file()):
        fail("unsafe absent marker")
    if kind == "plugins":
        target_list = root / "targets.tsv"
        if target_list.is_symlink() or not target_list.is_file():
            fail("missing target list")
        rows = [line.split("\t") for line in target_list.read_text().splitlines()]
        if len(rows) != 3 or any(len(row) != 8 for row in rows) or {row[7] for row in rows} != set(names):
            fail("invalid target list")
        absent_names = absent.read_text().splitlines() if absent.exists() else []
        if len(absent_names) != len(set(absent_names)) or not set(absent_names) <= set(names):
            fail("invalid absent list")
    else:
        if absent.exists() and absent.read_bytes():
            fail("invalid absent marker")
        absent_names = ["shaders"] if absent.exists() else []
    result = {}
    for name in names:
        target = root / name
        if target.is_symlink():
            fail(f"symlinked snapshot: {name}")
        if name in absent_names:
            if target.exists():
                fail(f"present snapshot marked absent: {name}")
            result[name] = None
            continue
        if not target.is_dir():
            fail(f"missing snapshot: {name}")
        entries = {}
        for child in sorted(target.rglob("*")):
            relative = child.relative_to(target).as_posix()
            if child.is_symlink():
                fail(f"symlink inside snapshot: {name}/{relative}")
            if child.is_dir():
                entries[relative + "/"] = None
            elif child.is_file():
                entries[relative] = hashlib.sha256(child.read_bytes()).hexdigest()
            else:
                fail(f"unsupported snapshot entry: {name}/{relative}")
        result[name] = entries
    return result


def main() -> None:
    if len(sys.argv) != 4 or sys.argv[1] not in {"create", "verify"} or sys.argv[2] not in {"plugins", "shaders"}:
        fail("usage: create|verify plugins|shaders BACKUP")
    operation, kind, path = sys.argv[1:]
    root = Path(path)
    if root.is_symlink() or not root.is_dir():
        fail("unsafe backup root")
    manifest = root / "manifest.json"
    actual = describe(root, kind)
    if operation == "create":
        if manifest.exists() or manifest.is_symlink():
            fail("manifest already exists")
        manifest.write_text(json.dumps(actual, sort_keys=True, separators=(",", ":")) + "\n")
    else:
        if manifest.is_symlink() or not manifest.is_file():
            fail("missing or symlinked manifest")
        try:
            expected = json.loads(manifest.read_text())
        except (OSError, ValueError) as exc:
            fail(f"invalid manifest: {exc}")
        if expected != actual:
            fail("snapshot content mismatch")


if __name__ == "__main__":
    main()
