"""Read-only, single-root local census for the provisional media policy.

Usage: uv run python -I checks/mba-media-census.py --root /absolute/root
       --role source|shadow --epoch E0|E1 [--asserted /path/manifest.json]

Output is one JSON object with `manifest` (the policy's global input envelope)
and `receipt` (local observation metadata). An asserted mismatch, incomplete
traversal, drift, unsafe entry, or I/O error returns 1 without a partial
manifest. This is not a signed, durable, remote, or live source verification.
Never run this collector against a cloud-backed or live music root without a
separate authorization and nonhydration review; tests use temp roots only.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import io
import json
import os
import posixpath
import stat
import sys
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "mba_media_policy", Path(__file__).with_name("mba-media-policy.py")
)
policy = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(policy)

CHUNK = 1024 * 1024
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
FILE_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0)


class CensusError(ValueError):
    """The complete independent local census could not be attested."""


def same_volume(entry: os.stat_result, device: int) -> bool:
    return entry.st_dev == device


def fingerprint(entry: os.stat_result) -> tuple[int, ...]:
    return (
        entry.st_dev, entry.st_ino, entry.st_mode, entry.st_size,
        entry.st_mtime_ns, entry.st_ctime_ns, getattr(entry, "st_flags", 0),
        getattr(entry, "st_blocks", -1),
    )


def is_placeholder(entry: os.stat_result) -> bool:
    # SF_DATALESS is the macOS dataless/FileProvider flag. Zero allocated
    # blocks for a nonempty file are conservatively rejected as well.
    return bool(getattr(entry, "st_flags", 0) & getattr(stat, "SF_DATALESS", 0)) or (
        stat.S_ISREG(entry.st_mode) and entry.st_size > 0
        and getattr(entry, "st_blocks", 1) == 0
    )


def scan_names(fd: int) -> list[str]:
    names: list[str] = []
    with os.scandir(fd) as stream:
        for entry in stream:
            names.append(entry.name)
            if len(names) > policy.MAX_ITEMS:
                raise CensusError("directory exceeds global item bound")
    return names


def read_hash(fd: int, playlist: bool) -> tuple[str, bytes | None, int]:
    digest = hashlib.sha256()
    data = bytearray() if playlist else None
    total = 0
    while True:
        chunk = os.read(fd, CHUNK)
        if not chunk:
            break
        total += len(chunk)
        if data is not None:
            if total > policy.MAX_BYTES:
                raise CensusError("playlist exceeds bounded envelope")
            data.extend(chunk)
        digest.update(chunk)
    return digest.hexdigest(), bytes(data) if data is not None else None, total


def references(data: bytes, remaining: int) -> list[str] | None:
    """Keep exact path whitespace; stop before exceeding the global ref budget."""
    refs: list[str] = []
    try:
        decoded = data.decode("utf-8-sig")
    except UnicodeError:
        return None  # Preserve/hash undecodable playlist bytes as a retained companion.
    for raw in io.StringIO(decoded):
        line = raw.removesuffix("\n").removesuffix("\r")
        if not line or line.startswith("#"):
            continue
        if len(refs) >= remaining:
            raise CensusError("excessive playlist references")
        if len(line.encode("utf-8")) > policy.MAX_PATH or any(ord(c) < 32 or ord(c) == 127 for c in line):
            return None
        refs.append(line)
    return refs


def resolve_references(rows: list[dict], root: Path) -> None:
    """Resolve playlist text only against the complete observed regular-file set.

    Preserve source bytes, order and repeated tracks. Root-relative, album-relative
    and same-root absolute paths may resolve; absent/ambiguous/outside references
    leave the playlist retained, without claiming it is usable for playback.
    """
    files = {row["path"] for row in rows if row["kind"] == "file"}
    for row in rows:
        if "references" not in row:
            continue
        resolved = []
        for original in row["references"]:
            reference = original.replace("\\", "/")
            if reference.startswith("/"):
                prefix = str(root) + "/"
                candidates = {posixpath.normpath(reference[len(prefix):])} if reference.startswith(prefix) else set()
            else:
                candidates = {posixpath.normpath(reference),
                    posixpath.normpath(posixpath.join(posixpath.dirname(row["path"]), reference))}
            matches = {path for path in candidates if policy.safe_path(path) and path in files}
            if len(matches) != 1:
                row.pop("references")
                break
            resolved.append(matches.pop())
        else:
            row["references"] = resolved


def walk(root_fd: int, root_stat: os.stat_result, *, hash_files: bool) -> tuple[list[dict[str, object]], dict[str, tuple[int, ...]], int]:
    """Scan relative to pinned directory descriptors, never resolving children."""
    rows: list[dict[str, object]] = []
    stamps: dict[str, tuple[int, ...]] = {"": fingerprint(root_stat)}
    hashed = 0
    reference_count = 0
    device = root_stat.st_dev

    def directory(fd: int, relative: str) -> None:
        nonlocal hashed, reference_count
        before = os.fstat(fd)
        if not same_volume(before, device) or is_placeholder(before):
            raise CensusError("directory left pinned local volume")
        names = scan_names(fd)
        # Independent listing detects a missing scandir entry, not just a
        # change between two invocations of the same incomplete traversal.
        if len(names) != len(set(names)) or set(names) != set(os.listdir(fd)):
            raise CensusError("incomplete directory enumeration")
        for name in sorted(names):
            path = f"{relative}/{name}" if relative else name
            if not policy.safe_path(path):
                raise CensusError("unsafe path")
            entry = os.stat(name, dir_fd=fd, follow_symlinks=False)
            if not same_volume(entry, device) or is_placeholder(entry):
                raise CensusError("entry left pinned local volume or is dataless")
            if stat.S_ISLNK(entry.st_mode):
                raise CensusError("symlink in census")
            stamps[path] = fingerprint(entry)
            if len(stamps) - 1 > policy.MAX_ITEMS:
                raise CensusError("global item bound exceeded")
            if stat.S_ISDIR(entry.st_mode):
                child_fd = os.open(name, DIR_FLAGS, dir_fd=fd)
                try:
                    if fingerprint(os.fstat(child_fd)) != fingerprint(entry):
                        raise CensusError("directory changed during open")
                    rows.append({"path": path, "kind": "directory", "readable": True, "local": True})
                    directory(child_fd, path)
                    if fingerprint(os.fstat(child_fd)) != fingerprint(entry):
                        raise CensusError("directory drift")
                finally:
                    os.close(child_fd)
            elif stat.S_ISREG(entry.st_mode):
                row: dict[str, object] = {"path": path, "kind": "file", "readable": True, "local": True}
                if hash_files:
                    child_fd = os.open(name, FILE_FLAGS, dir_fd=fd)
                    try:
                        if fingerprint(os.fstat(child_fd)) != fingerprint(entry):
                            raise CensusError("file changed during open")
                        digest, content, size = read_hash(child_fd, path.casefold().endswith(".m3u"))
                        if size != entry.st_size or fingerprint(os.fstat(child_fd)) != fingerprint(entry):
                            raise CensusError("file changed during hashing")
                        row.update(size=size, sha256=digest)
                        if content is not None:
                            refs = references(content, policy.MAX_REFERENCES - reference_count)
                            if refs is not None:
                                reference_count += len(refs)
                                row["references"] = refs
                        hashed += 1
                    finally:
                        os.close(child_fd)
                rows.append(row)
                if fingerprint(os.stat(name, dir_fd=fd, follow_symlinks=False)) != fingerprint(entry):
                    raise CensusError("file path drift")
            else:
                raise CensusError("unsupported filesystem entry")
        if fingerprint(os.fstat(fd)) != fingerprint(before) or set(scan_names(fd)) != set(os.listdir(fd)) or set(names) != set(os.listdir(fd)):
            raise CensusError("directory changed or traversal incomplete")
        if fingerprint(os.fstat(fd)) != stamps[relative]:
            raise CensusError("directory drift")

    directory(root_fd, "")
    return rows, stamps, hashed


def open_pinned_root(root: Path) -> int:
    # Open every lexical ancestor without following links, including the root.
    # Require an absolute, literal path; callers cannot sneak in '..'.
    if not root.is_absolute() or any(part in (".", "..") for part in root.parts):
        raise CensusError("root must be an absolute literal directory")
    fd = os.open("/", DIR_FLAGS)
    try:
        for part in root.parts[1:]:
            next_fd = os.open(part, DIR_FLAGS, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        return fd
    except BaseException:
        os.close(fd)
        raise


def collect(root: Path, role: str, epoch: str, asserted: object | None = None) -> dict[str, object]:
    if role not in ("source", "shadow") or epoch not in ("E0", "E1"):
        raise CensusError("invalid role or epoch")
    try:
        root_fd = open_pinned_root(root)
        try:
            root_stat = os.fstat(root_fd)
            if is_placeholder(root_stat):
                raise CensusError("dataless root")
            rows, first, hashed = walk(root_fd, root_stat, hash_files=True)
            other, second, _ = walk(root_fd, root_stat, hash_files=False)
            if first != second or [row["path"] for row in rows] != [row["path"] for row in other]:
                raise CensusError("source drift across traversal")
            if fingerprint(os.fstat(root_fd)) != fingerprint(root_stat):
                raise CensusError("root drift")
            # A directory fd remains valid after a rename. Reopen the literal
            # root and check descendants once more to reject a nested swap
            # after the second pass. This does not make the scan atomic.
            check_fd = open_pinned_root(root)
            try:
                check_stat = os.fstat(check_fd)
                if fingerprint(check_stat) != fingerprint(root_stat):
                    raise CensusError("root path drift")
                final_rows, final_stamps, _ = walk(check_fd, check_stat, hash_files=False)
                if final_stamps != first or [row["path"] for row in final_rows] != [row["path"] for row in rows]:
                    raise CensusError("source drift at final path check")
            finally:
                os.close(check_fd)
        finally:
            os.close(root_fd)
        keys = [policy.collision_key(row["path"]) for row in rows]
        if len(keys) != len(set(keys)):
            raise CensusError("global case or Unicode collision")
        resolve_references(rows, root)
        manifest = {"schema_version": 1, "epoch": epoch, "role": role, "items": rows}
        policy.validate(manifest, role=role)
        serialized = json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
        if len(serialized) > policy.MAX_BYTES:
            raise CensusError("manifest byte bound exceeded")
        receipt: dict[str, object] = {
            "status": "closed_local_census", "coverage": "local_observation_only",
            "algorithm": "sha256", "root_device": root_stat.st_dev,
            "root_inode": root_stat.st_ino, "rows": len(rows),
            "hashed_files": hashed, "manifest_sha256": hashlib.sha256(serialized).hexdigest(),
        }
        if asserted is not None:
            policy.validate(asserted, role=role)
            if (asserted["epoch"] != epoch or
                    sorted(asserted["items"], key=lambda row: row["path"]) !=
                    sorted(rows, key=lambda row: row["path"])):
                raise CensusError("asserted manifest mismatch")
            receipt["asserted_match"] = True
        return {"manifest": manifest, "receipt": receipt}
    except (OSError, UnicodeError, ValueError, TypeError, RecursionError) as error:
        raise CensusError("census not closed") from error


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--role", choices=("source", "shadow"), required=True)
    parser.add_argument("--epoch", choices=("E0", "E1"), required=True)
    parser.add_argument("--asserted", type=Path)
    args = parser.parse_args(argv)
    try:
        asserted = policy.read_document(args.asserted) if args.asserted else None
        result = collect(args.root, args.role, args.epoch, asserted)
    except (OSError, UnicodeError, ValueError, TypeError, RecursionError):
        print("error: local census not closed", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
