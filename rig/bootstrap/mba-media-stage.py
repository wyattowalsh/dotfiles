"""Additive, serial E0 staging and the existing offline/disposable helpers.

Production pulls a frozen census over strict SSH into a new private, pinned
staging root. It never publishes a reader/writer epoch or removes source data.
The older fixture-only entry points retain their disposable-root boundary.
"""
from __future__ import annotations

import argparse
import ctypes
import fcntl
import hashlib
import importlib.util
import json
import os
import re
import shlex
import signal
import socket
import stat
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Callable

POLICY_FILE = Path(__file__).parents[2] / "checks" / "mba-media-policy.py"
_spec = importlib.util.spec_from_file_location("mba_media_stage_policy", POLICY_FILE)
policy = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(policy)
DIR = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
READ = os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0)
CREATE = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
CHUNK = 1024 * 1024
UNSERVED = "UNserved"
DEFAULT_MAX_ENTRIES = policy.MAX_ITEMS
DEFAULT_MAX_BYTES = policy.MAX_BYTES
MAX_CAMPAIGN_ENTRIES = 100_000


class StageError(ValueError):
    """An assertion failed; do not stage or publish anything."""


def _entry_limit(value: object) -> int:
    if type(value) is not int or not 1 <= value <= MAX_CAMPAIGN_ENTRIES:
        raise StageError("whole-census entry limit must be 1..100000")
    return value


def _campaign_limit(document: dict) -> int:
    return _entry_limit(document.get("max_entries", DEFAULT_MAX_ENTRIES))


@contextmanager
def _envelope_bounds(max_entries: int):
    """One complete manifest, never separately accepted partial batches."""
    old = policy.MAX_ITEMS, policy.MAX_BYTES
    policy.MAX_ITEMS = _entry_limit(max_entries)
    policy.MAX_BYTES = max(DEFAULT_MAX_BYTES, policy.MAX_ITEMS * 2400)
    try:
        yield
    finally:
        policy.MAX_ITEMS, policy.MAX_BYTES = old


def _digest(manifest: dict) -> str:
    payload = json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    if len(payload) > policy.MAX_BYTES:
        raise StageError("oversize manifest")
    return hashlib.sha256(payload).hexdigest()


def validate_census(envelope: object) -> tuple[dict, dict]:
    if not isinstance(envelope, dict) or set(envelope) != {"manifest", "receipt"}:
        raise StageError("invalid census envelope")
    manifest, receipt = envelope["manifest"], envelope["receipt"]
    policy.validate(manifest, role="source")
    items = manifest["items"]
    if not isinstance(receipt, dict) or set(receipt) - {
        "status", "coverage", "algorithm", "root_device", "root_inode", "rows",
        "hashed_files", "manifest_sha256", "asserted_match",
    } or set(receipt) < {
        "status", "coverage", "algorithm", "root_device", "root_inode", "rows",
        "hashed_files", "manifest_sha256",
    }:
        raise StageError("invalid receipt")
    if (receipt["status"], receipt["coverage"], receipt["algorithm"]) != (
        "closed_local_census", "local_observation_only", "sha256"
    ) or ("asserted_match" in receipt and receipt["asserted_match"] is not True):
        raise StageError("untrusted receipt")
    if any(type(receipt[k]) is not int or receipt[k] < 0 for k in ("root_device", "root_inode", "rows", "hashed_files")):
        raise StageError("invalid root identity/count")
    if not receipt["root_device"] or not receipt["root_inode"] or not items:
        raise StageError("empty or unidentified root")
    if receipt["rows"] != len(items) or receipt["hashed_files"] != sum(x["kind"] == "file" for x in items):
        raise StageError("incomplete receipt")
    if receipt["manifest_sha256"] != _digest(manifest):
        raise StageError("manifest digest mismatch")
    paths = [x["path"] for x in items]
    keys = [policy.collision_key(x) for x in paths]
    if len(set(keys)) != len(keys):
        raise StageError("colliding paths")
    directories = {x["path"] for x in items if x["kind"] == "directory"}
    for row in items:
        path = row["path"]
        if not policy.safe_path(path) or row["kind"] not in ("file", "directory") or not row["local"] or not row["readable"]:
            raise StageError("unsafe, unreadable or nonlocal item")
        if any("/".join(path.split("/")[:n]) not in directories for n in range(1, len(path.split("/")))):
            raise StageError("missing directory ancestor")
        if row["kind"] == "file" and ("size" not in row or "sha256" not in row):
            raise StageError("unhashed file")
    return manifest, receipt


def plan(envelope: object) -> dict:
    manifest, receipt = validate_census(envelope)
    classified = policy.classify(manifest["items"])["items"]
    included = [item for item, row in zip(manifest["items"], classified, strict=True)
                if item["kind"] == "file" and policy.copy_included(row)]
    unresolved_count = sum(row["disposition"] == "unresolved"
                           and row["reasons"] != ["not_regular_file"] for row in classified)
    return {"operation": "offline_plan_only", "epoch": manifest["epoch"],
            "status": "blocked" if unresolved_count else "provisional",
            "coverage": "local_observation_only", "manifest_sha256": receipt["manifest_sha256"],
            "file_count": len(included), "total_bytes": sum(x["size"] for x in included),
            "retained_companion_count": sum(row["disposition"] == "retained_companion" for row in classified),
            "unresolved_count": unresolved_count, "destination": f"{UNSERVED}/ (not created)",
            "publication": "forbidden"}


def _root(path: Path) -> int:
    # Reject nonliteral roots and symlinks at every ancestor, including /tmp aliases.
    text = os.fspath(path)
    if not text.startswith("/") or text != os.path.normpath(text) or any(p in (".", "..") for p in text.split("/")):
        raise StageError("root must be a literal absolute path")
    fd = os.open("/", DIR)
    try:
        for part in path.parts[1:]:
            next_fd = os.open(part, DIR, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        return fd
    except BaseException:
        os.close(fd)
        raise


def _fixture_boundary(fixture_root: Path, source_root: Path, destination_root: Path) -> None:
    """Only direct child roots of a private, system-temporary fixture are writable."""
    allowed = (Path("/private/tmp"), Path(os.path.realpath(tempfile.gettempdir())))
    if (source_root.parent != fixture_root or destination_root.parent != fixture_root
            or source_root == destination_root):
        raise StageError("fixture roots must be distinct direct children")
    if not any(fixture_root != base and base in fixture_root.parents for base in allowed):
        raise StageError("fixture must live under the system temporary area")
    fd = _root(fixture_root)
    try:
        entry = os.fstat(fd)
        if entry.st_uid != os.getuid() or stat.S_IMODE(entry.st_mode) & 0o077:
            raise StageError("fixture directory must be private and owned by caller")
    finally:
        os.close(fd)


def _child(parent: int, name: str, device: int) -> int:
    fd = os.open(name, DIR, dir_fd=parent)
    if os.fstat(fd).st_dev != device:
        os.close(fd)
        raise StageError("directory crossed volume")
    return fd


def _regular(entry: os.stat_result, device: int) -> None:
    if (not stat.S_ISREG(entry.st_mode) or entry.st_dev != device or entry.st_nlink != 1
            or getattr(entry, "st_flags", 0) & getattr(stat, "SF_DATALESS", 0)
            or (entry.st_size and getattr(entry, "st_blocks", 1) == 0)):
        raise StageError("nonlocal, hardlinked, or nonregular file")


def _stamp(entry: os.stat_result) -> tuple:
    return (entry.st_dev, entry.st_ino, entry.st_mode, entry.st_nlink,
            entry.st_size, entry.st_mtime_ns, entry.st_ctime_ns,
            getattr(entry, "st_flags", 0), getattr(entry, "st_blocks", -1))


def _hash_fd(fd: int, expected: dict, device: int) -> None:
    before = os.fstat(fd)
    _regular(before, device)
    digest = hashlib.sha256()
    total = 0
    while chunk := os.read(fd, CHUNK):
        total += len(chunk)
        if total > expected["size"]:
            raise StageError("size changed")
        digest.update(chunk)
    if total != expected["size"] or digest.hexdigest() != expected["sha256"] or _stamp(os.fstat(fd)) != _stamp(before):
        raise StageError("bytes or identity changed")


def _sync_json(parent: int, name: str, data: dict, *, replace: bool) -> None:
    payload = json.dumps(data, sort_keys=True, separators=(",", ":")).encode()
    temp = f".{name}.new-{os.getpid()}"
    fd = os.open(temp, CREATE, 0o600, dir_fd=parent)
    try:
        with os.fdopen(fd, "wb", closefd=False) as stream:
            stream.write(payload)
            stream.flush()
        os.fsync(fd)
    except BaseException:
        os.unlink(temp, dir_fd=parent)
        raise
    finally:
        os.close(fd)
    if replace:
        os.replace(temp, name, src_dir_fd=parent, dst_dir_fd=parent)
    else:
        try:
            os.link(temp, name, src_dir_fd=parent, dst_dir_fd=parent, follow_symlinks=False)
        finally:
            os.unlink(temp, dir_fd=parent)
    os.fsync(parent)


def _read_journal(parent: int, name: str) -> dict | None:
    try:
        fd = os.open(name, READ, dir_fd=parent)
    except FileNotFoundError:
        return None
    try:
        entry = os.fstat(fd)
        _regular(entry, entry.st_dev)
        if entry.st_size > 4096:
            raise StageError("oversize journal")
        data = json.loads(os.read(fd, 4097))
        if not isinstance(data, dict):
            raise StageError("invalid journal")
        return data
    finally:
        os.close(fd)


def _cohort(manifest: dict, receipt: dict, destination: os.stat_result) -> dict:
    return {"epoch": manifest["epoch"], "manifest_sha256": receipt["manifest_sha256"],
            "source_device": receipt["root_device"], "source_inode": receipt["root_inode"],
            "destination_device": destination.st_dev, "destination_inode": destination.st_ino}


def _pin_cohort(journal: int, expected: dict, *, create: bool) -> None:
    """Pin the entire destination before any per-file pre-journal is written."""
    current = _read_journal(journal, ".cohort.json")
    if current is None:
        if not create:
            raise StageError("destination has no durable cohort pin")
        _sync_json(journal, ".cohort.json", expected, replace=False)
    elif current != expected:
        raise StageError("destination belongs to another census or epoch")


def _rename_exclusive(src_dir: int, src: str, dst_dir: int, dst: str) -> None:
    """Same-volume atomic rename with no-overwrite; refuse unsupported platforms."""
    libc = ctypes.CDLL(None, use_errno=True)
    if sys.platform == "darwin" and hasattr(libc, "renameatx_np"):
        call = libc.renameatx_np
        flags = 0x00000004  # RENAME_EXCL
    elif sys.platform.startswith("linux") and hasattr(libc, "renameat2"):
        call = libc.renameat2
        flags = 1  # RENAME_NOREPLACE
    else:
        raise StageError("exclusive rename unavailable")
    call.argtypes = (ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint)
    call.restype = ctypes.c_int
    if call(src_dir, os.fsencode(src), dst_dir, os.fsencode(dst), flags) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), dst)


def _entry_exists(parent: int, name: str) -> bool:
    try:
        os.stat(name, dir_fd=parent, follow_symlinks=False)
        return True
    except FileNotFoundError:
        return False


def _check_existing(parent: int, name: str, expected: dict, device: int) -> bool:
    try:
        fd = os.open(name, READ, dir_fd=parent)
    except FileNotFoundError:
        return False
    try:
        _hash_fd(fd, expected, device)
        return True
    finally:
        os.close(fd)


def recover_fixture(source_root: Path, destination_root: Path, envelope: dict, relative: str,
                    *, fixture_root: Path) -> str:
    """Inspect one durable journal; never delete, overwrite or retry uncertain work."""
    _fixture_boundary(fixture_root, source_root, destination_root)
    manifest, receipt = validate_census(envelope)
    rows = {row["path"]: row for row in manifest["items"] if row["kind"] == "file"}
    if relative not in rows:
        raise StageError("unasserted file")
    src_fd = _root(source_root)
    opened = [src_fd]
    try:
        dst_fd = _root(destination_root)
        opened.append(dst_fd)
        if (os.fstat(src_fd).st_dev, os.fstat(src_fd).st_ino) != (receipt["root_device"], receipt["root_inode"]):
            raise StageError("source root identity changed")
        device = os.fstat(dst_fd).st_dev
        if (device, os.fstat(dst_fd).st_ino) == (receipt["root_device"], receipt["root_inode"]):
            raise StageError("source and destination are identical")
        target = _child(dst_fd, UNSERVED, device); opened.append(target)
        journal = _child(target, ".journal", device); opened.append(journal)
        lock = os.open(".stage.lock", os.O_RDWR | os.O_NOFOLLOW, dir_fd=journal); opened.append(lock)
        _regular(os.fstat(lock), device)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise StageError("another file is in flight") from error
        _pin_cohort(journal, _cohort(manifest, receipt, os.fstat(dst_fd)), create=False)
        source_dir = src_fd
        for part in relative.split("/")[:-1]:
            source_dir = _child(source_dir, part, receipt["root_device"]); opened.append(source_dir)
            target = _child(target, part, device); opened.append(target)
        name = relative.split("/")[-1]
        record_name = hashlib.sha256(relative.encode()).hexdigest() + ".json"
        record = _read_journal(journal, record_name)
        if record is None:
            if _entry_exists(target, name):
                raise StageError("unrecorded final collision")
            return "new"
        expected_record = {"path": relative, "manifest_sha256": receipt["manifest_sha256"],
                           "source_device": receipt["root_device"], "source_inode": receipt["root_inode"],
                           "destination_device": device, "destination_inode": os.fstat(dst_fd).st_ino,
                           "temp": ".stage-" + hashlib.sha256(relative.encode()).hexdigest(),
                           "phase": record.get("phase")}
        if record != expected_record or record["phase"] not in ("pre", "post"):
            raise StageError("journal identity mismatch")
        try:
            os.stat(record["temp"], dir_fd=target, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise StageError("interrupted temp requires manual inspection")
        source_fd = os.open(name, READ, dir_fd=source_dir); opened.append(source_fd)
        _hash_fd(source_fd, rows[relative], receipt["root_device"])
        if not _check_existing(target, name, rows[relative], device):
            raise StageError("journal without verified final")
        if record["phase"] == "pre":
            # A verified pathname can be swapped before a post update. Never
            # manufacture completion for an interrupted promotion.
            raise StageError("verified final has pre journal; manual adjudication required")
        # A successful pathname check is not a pin: verify the current entry
        # again before reporting completion, even if it changed after that check.
        final_fd = os.open(name, READ, dir_fd=target); opened.append(final_fd)
        _hash_fd(final_fd, rows[relative], device)
        if _stamp(os.stat(name, dir_fd=target, follow_symlinks=False)) != _stamp(os.fstat(final_fd)):
            raise StageError("final path changed after recovery verification")
        return "complete"
    finally:
        for fd in reversed(opened):
            os.close(fd)


def stage_fixture(source_root: Path, destination_root: Path, envelope: dict, relative: str,
                  *, fixture_root: Path, low_water: int,
                  fault: Callable[[str], None] | None = None) -> str:
    """One-file disposable-root writer; all paths/identities rechecked under fd pins.

    Caller must precreate UNserved/.journal and asserted destination directories.
    A pre-journal/temp failure intentionally leaves evidence for manual recovery.
    """
    _fixture_boundary(fixture_root, source_root, destination_root)
    if type(low_water) is not int or low_water < 0:
        raise StageError("invalid low water")
    manifest, receipt = validate_census(envelope)
    rows = {row["path"]: row for row in manifest["items"] if row["kind"] == "file"}
    classifications = policy.classify(manifest["items"])["items"]
    included = {row["path"] for row, label in zip(manifest["items"], classifications, strict=True)
                if label["served"] == "include"}
    if relative not in rows or relative not in included:
        raise StageError("not an included asserted file")
    source = rows[relative]
    src_fd = _root(source_root)
    opened = [src_fd]
    try:
        dst_fd = _root(destination_root)
        opened.append(dst_fd)
        src_stat, dst_stat = os.fstat(src_fd), os.fstat(dst_fd)
        if (src_stat.st_dev, src_stat.st_ino) != (receipt["root_device"], receipt["root_inode"]):
            raise StageError("source root identity changed")
        if (src_stat.st_dev, src_stat.st_ino) == (dst_stat.st_dev, dst_stat.st_ino):
            raise StageError("same root")
        # Lock first, before any journal or temp changes. No second in-flight writer.
        target = _child(dst_fd, UNSERVED, dst_stat.st_dev); opened.append(target)
        journal = _child(target, ".journal", dst_stat.st_dev); opened.append(journal)
        lock = os.open(".stage.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600, dir_fd=journal)
        opened.append(lock)
        _regular(os.fstat(lock), dst_stat.st_dev)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise StageError("another file is in flight") from error
        expected_cohort = _cohort(manifest, receipt, dst_stat)
        _pin_cohort(journal, expected_cohort, create=True)
        source_dir = src_fd
        for part in relative.split("/")[:-1]:
            source_dir = _child(source_dir, part, src_stat.st_dev); opened.append(source_dir)
            target = _child(target, part, dst_stat.st_dev); opened.append(target)
        name = relative.split("/")[-1]
        before = os.stat(name, dir_fd=source_dir, follow_symlinks=False)
        _regular(before, src_stat.st_dev)
        read_fd = os.open(name, READ, dir_fd=source_dir); opened.append(read_fd)
        if _stamp(before) != _stamp(os.fstat(read_fd)):
            raise StageError("source changed during open")
        record_name = hashlib.sha256(relative.encode()).hexdigest() + ".json"
        temp = ".stage-" + hashlib.sha256(relative.encode()).hexdigest()
        if _read_journal(journal, record_name) is not None or _entry_exists(target, name):
            raise StageError("journal or destination collision; inspect recovery")
        if os.statvfs(dst_fd).f_bavail * os.statvfs(dst_fd).f_frsize - source["size"] < low_water:
            raise StageError("low-water hard stop")
        record = {"path": relative, "manifest_sha256": receipt["manifest_sha256"],
                  "source_device": src_stat.st_dev, "source_inode": src_stat.st_ino,
                  "destination_device": dst_stat.st_dev, "destination_inode": dst_stat.st_ino,
                  "temp": temp, "phase": "pre"}
        _sync_json(journal, record_name, record, replace=False)
        if fault: fault("after_pre")
        write_fd = os.open(temp, CREATE, 0o600, dir_fd=target); opened.append(write_fd)
        digest = hashlib.sha256()
        copied = 0
        while chunk := os.read(read_fd, CHUNK):
            copied += len(chunk)
            if copied > source["size"]:
                raise StageError("source size drift")
            view = memoryview(chunk)
            while view:
                view = view[os.write(write_fd, view):]
            digest.update(chunk)
            if os.statvfs(dst_fd).f_bavail * os.statvfs(dst_fd).f_frsize < low_water:
                raise StageError("low-water hard stop during write")
            if fault: fault("during_write")
        if copied != source["size"] or digest.hexdigest() != source["sha256"]:
            raise StageError("source bytes differ from frozen assertion")
        if _stamp(os.fstat(read_fd)) != _stamp(before) or _stamp(os.stat(name, dir_fd=source_dir, follow_symlinks=False)) != _stamp(before):
            raise StageError("source drift after read")
        if os.fstat(write_fd).st_size != copied or os.fstat(write_fd).st_dev != dst_stat.st_dev:
            raise StageError("temp size/volume drift")
        if fault: fault("before_fsync")
        os.fsync(write_fd)
        if fault: fault("after_fsync")
        if os.statvfs(dst_fd).f_bavail * os.statvfs(dst_fd).f_frsize < low_water:
            raise StageError("low-water hard stop after write")
        os.fsync(target)
        if fault: fault("before_rename")
        if (_stamp(os.stat(temp, dir_fd=target, follow_symlinks=False)) != _stamp(os.fstat(write_fd))
                or _stamp(os.stat(name, dir_fd=source_dir, follow_symlinks=False)) != _stamp(before)):
            raise StageError("temp or source changed before rename")
        _rename_exclusive(target, temp, target, name)
        os.fsync(target)
        if fault: fault("after_rename")
        final_fd = os.open(name, READ, dir_fd=target); opened.append(final_fd)
        if (_stamp(os.fstat(final_fd)) != _stamp(os.fstat(write_fd))
                or _stamp(os.stat(name, dir_fd=target, follow_symlinks=False)) != _stamp(os.fstat(write_fd))):
            raise StageError("renamed file identity changed")
        _hash_fd(final_fd, source, dst_stat.st_dev)
        if _stamp(os.stat(name, dir_fd=target, follow_symlinks=False)) != _stamp(os.fstat(final_fd)):
            raise StageError("final path changed before journal post")
        _pin_cohort(journal, expected_cohort, create=False)
        # The pin check can take time; revalidate both bytes and pathname
        # identity immediately before persisting the post journal.
        os.lseek(final_fd, 0, os.SEEK_SET)
        _hash_fd(final_fd, source, dst_stat.st_dev)
        if _stamp(os.stat(name, dir_fd=target, follow_symlinks=False)) != _stamp(os.fstat(final_fd)):
            raise StageError("final path changed after cohort pin")
        _sync_json(journal, record_name, {**record, "phase": "post"}, replace=True)
        return "complete"
    finally:
        for fd in reversed(opened):
            os.close(fd)


def _absolute(value: object) -> Path:
    if (not isinstance(value, str) or not value.startswith("/") or value == "/"
            or value != os.path.normpath(value) or any(ord(c) < 32 for c in value)
            or ".." in value.split("/")):
        raise StageError("literal absolute path required")
    return Path(value)


def _closed(value: object, names: set[str]) -> dict:
    if not isinstance(value, dict) or set(value) != names:
        raise StageError("invalid production schema")
    return value


def _positive(value: object) -> int:
    if type(value) is not int or not 0 < value < 2**63:
        raise StageError("positive bounded integer required")
    return value


def _sha(value: object) -> str:
    if not isinstance(value, str) or re.fullmatch("[0-9a-f]{64}", value) is None:
        raise StageError("SHA-256 required")
    return value


def _instant(value: object) -> datetime:
    if not isinstance(value, str):
        raise StageError("UTC timestamp required")
    result = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    if result.strftime("%Y-%m-%dT%H:%M:%SZ") != value:
        raise StageError("UTC timestamp required")
    return result


def private_json(path: Path, limit: int) -> dict:
    """Read explicit owner-only input, with no symlink or path-swap adoption."""
    path = _absolute(os.fspath(path))
    parent = _root(path.parent)
    try:
        fd = os.open(path.name, READ, dir_fd=parent)
        try:
            before = os.fstat(fd)
            _regular(before, before.st_dev)
            if before.st_uid != os.getuid() or stat.S_IMODE(before.st_mode) & 0o077 or before.st_size > limit:
                raise StageError("input must be private, owned and bounded")
            parts, total = [], 0
            while chunk := os.read(fd, min(CHUNK, limit + 1 - total)):
                parts.append(chunk)
                total += len(chunk)
                if total > limit:
                    raise StageError("oversize private input")
            data = b"".join(parts)
            if len(data) != before.st_size or _stamp(os.fstat(fd)) != _stamp(before):
                raise StageError("input changed while reading")
            if _stamp(os.stat(path.name, dir_fd=parent, follow_symlinks=False)) != _stamp(before):
                raise StageError("input pathname changed")
            def unique(pairs):
                output = {}
                for key, value in pairs:
                    if key in output:
                        raise StageError("duplicate input field")
                    output[key] = value
                return output
            result = json.loads(data, object_pairs_hook=unique)
            if not isinstance(result, dict):
                raise StageError("dictionary required")
            return result
        finally:
            os.close(fd)
    finally:
        os.close(parent)


def _eligible(envelope: dict) -> tuple[dict, dict, list[dict]]:
    manifest, receipt = validate_census(envelope)
    if manifest["epoch"] != "E0" or plan(envelope)["unresolved_count"]:
        raise StageError("production needs a fully classified E0 census")
    labels = policy.classify(manifest["items"])["items"]
    files = [row for row, label in zip(manifest["items"], labels, strict=True)
             if row["kind"] == "file" and policy.copy_included(label)]
    if not files:
        raise StageError("empty eligible set")
    return manifest, receipt, sorted(files, key=lambda row: row["path"])


def validate_contract(contract: dict, envelope: dict) -> tuple[dict, dict, list[dict]]:
    optional = {"max_entries"} if isinstance(contract, dict) and "max_entries" in contract else set()
    _closed(contract, {"schema_version", "campaign_id", "epoch", "manifest_sha256", "started_at",
                       "capacity_receipt_sha256", "source", "target"} | optional)
    max_entries = _campaign_limit(contract)
    if type(contract["schema_version"]) is not int or contract["schema_version"] != 1 or contract["epoch"] != "E0":
        raise StageError("only E0 production staging is supported")
    if not isinstance(contract["campaign_id"], str) or re.fullmatch("[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", contract["campaign_id"]) is None:
        raise StageError("literal campaign ID required")
    _sha(contract["capacity_receipt_sha256"])
    if _instant(contract["started_at"]) > datetime.now(timezone.utc):
        raise StageError("campaign start cannot be in the future")
    source = _closed(contract["source"], {"hostname", "root", "device", "inode", "ssh_host", "ssh_user",
        "ssh_port", "identity_file", "identity_device", "identity_inode", "known_hosts_file",
        "known_hosts_sha256", "python", "script", "script_sha256", "census"})
    target = _closed(contract["target"], {"hostname", "root", "device", "inode", "mountpoint",
        "volume_uuid", "filesystem_capacity_bytes", "low_water_bytes", "reserved_bytes",
        "observed_free_bytes", "observed_at"})
    for part in (source, target):
        if not isinstance(part["hostname"], str) or not part["hostname"] or any(c.isspace() for c in part["hostname"]):
            raise StageError("host identity required")
        for name in ("device", "inode"):
            _positive(part[name])
        _absolute(part["root"])
    if source["hostname"] == target["hostname"]:
        raise StageError("distinct source and target hosts required")
    for name in ("identity_file", "known_hosts_file", "python", "script", "census"):
        _absolute(source[name])
    for name in ("identity_device", "identity_inode", "ssh_port"):
        _positive(source[name])
    if source["ssh_port"] > 65535 or not isinstance(source["ssh_host"], str) or re.fullmatch("[A-Za-z0-9][A-Za-z0-9_.:-]*", source["ssh_host"]) is None:
        raise StageError("invalid SSH target")
    if not isinstance(source["ssh_user"], str) or re.fullmatch("[A-Za-z_][A-Za-z0-9_-]*", source["ssh_user"]) is None:
        raise StageError("invalid SSH user")
    _sha(source["script_sha256"])
    _sha(source["known_hosts_sha256"])
    mountpoint = _absolute(target["mountpoint"])
    if not _absolute(target["root"]).is_relative_to(mountpoint):
        raise StageError("staging root must be on pinned mount")
    if not isinstance(target["volume_uuid"], str) or not target["volume_uuid"]:
        raise StageError("volume UUID required")
    for name in ("filesystem_capacity_bytes", "low_water_bytes", "reserved_bytes", "observed_free_bytes"):
        _positive(target[name])
    if target["observed_free_bytes"] > target["filesystem_capacity_bytes"]:
        raise StageError("invalid initial capacity")
    if not timedelta() <= _instant(contract["started_at"]) - _instant(target["observed_at"]) <= timedelta(hours=1):
        raise StageError("capacity observation must be fresh at campaign start")
    with _envelope_bounds(max_entries):
        manifest, receipt, files = _eligible(envelope)
    if (_sha(contract["manifest_sha256"]) != receipt["manifest_sha256"]
            or (source["device"], source["inode"]) != (receipt["root_device"], receipt["root_inode"])):
        raise StageError("contract does not bind the frozen census")
    return manifest, receipt, files


def _owned_directory(fd: int) -> None:
    entry = os.fstat(fd)
    if entry.st_uid != os.getuid() or stat.S_IMODE(entry.st_mode) & 0o077:
        raise StageError("staging directories must be private and owned")


def _directory(parent: int, name: str, device: int) -> int:
    try:
        os.mkdir(name, 0o700, dir_fd=parent)
        os.fsync(parent)
    except FileExistsError:
        pass
    fd = _child(parent, name, device)
    try:
        _owned_directory(fd)
    except BaseException:
        os.close(fd)
        raise
    return fd


def _observe_target(target: dict, fd: int) -> None:
    """Reuse the existing OS/APFS observer; tests substitute only this OS edge."""
    if socket.gethostname() != target["hostname"]:
        raise StageError("wrong target host")
    if (os.fstat(fd).st_dev, os.fstat(fd).st_ino) != (target["device"], target["inode"]):
        raise StageError("target root identity changed")
    current = _root(_absolute(target["root"]))
    try:
        if (os.fstat(current).st_dev, os.fstat(current).st_ino) != (target["device"], target["inode"]):
            raise StageError("target pathname changed")
    finally:
        os.close(current)
    directory = Path(__file__).with_name("mba-navidrome")
    if "mba_navidrome_guard" not in sys.modules:
        spec = importlib.util.spec_from_file_location("mba_navidrome_guard", directory / "guard.py")
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
    spec = importlib.util.spec_from_file_location("mba_stage_volume_observer", directory / "volume-observer.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    volume = module.MacOSVolumeObserver(_absolute(target["mountpoint"]))(_absolute(target["root"]))
    if volume.apfs_uuid.lower() != target["volume_uuid"].lower() or volume.apfs_role.lower() != "data" or volume.internal is not True:
        raise StageError("target APFS identity changed")
    space = os.fstatvfs(fd)
    if space.f_blocks * space.f_frsize != target["filesystem_capacity_bytes"]:
        raise StageError("target filesystem capacity changed")


def _capacity(fd: int, target: dict, pending_bytes: int) -> None:
    space = os.fstatvfs(fd)
    free = space.f_bavail * space.f_frsize
    if free - pending_bytes < target["low_water_bytes"] + target["reserved_bytes"]:
        raise StageError("production capacity hard stop")


def _source_request(contract: dict, relative: str | None) -> dict:
    source = contract["source"]
    request = {"schema_version": 1, "operation": "verify" if relative is None else "file",
        "hostname": source["hostname"], "root": source["root"], "device": source["device"],
        "inode": source["inode"], "census": source["census"], "script_sha256": source["script_sha256"],
        "manifest_sha256": contract["manifest_sha256"], "epoch": "E0", "relative": relative}
    if "max_entries" in contract:
        request["max_entries"] = _campaign_limit(contract)
    return request


def _ssh_argv(source: dict) -> list[str]:
    """No default SSH config, agent, host-key substitution or prompt fallback."""
    key = _absolute(source["identity_file"])
    parent = _root(key.parent)
    try:
        entry = os.stat(key.name, dir_fd=parent, follow_symlinks=False)
        _regular(entry, source["identity_device"])
        if (entry.st_dev, entry.st_ino) != (source["identity_device"], source["identity_inode"]) or entry.st_uid != os.getuid() or stat.S_IMODE(entry.st_mode) != 0o600:
            raise StageError("SSH identity metadata changed")
    finally:
        os.close(parent)
    hosts = _absolute(source["known_hosts_file"])
    parent = _root(hosts.parent)
    try:
        fd = os.open(hosts.name, READ, dir_fd=parent)
        try:
            entry = os.fstat(fd)
            _regular(entry, entry.st_dev)
            if entry.st_uid != os.getuid() or stat.S_IMODE(entry.st_mode) & 0o077 or entry.st_size > 65536:
                raise StageError("host pins must be private and bounded")
            data = os.read(fd, 65537)
            if (hashlib.sha256(data).hexdigest() != source["known_hosts_sha256"]
                    or _stamp(os.fstat(fd)) != _stamp(entry)
                    or _stamp(os.stat(hosts.name, dir_fd=parent, follow_symlinks=False)) != _stamp(entry)):
                raise StageError("SSH host pins changed")
        finally:
            os.close(fd)
    finally:
        os.close(parent)
    options = ["BatchMode=yes", "IdentitiesOnly=yes", "IdentityAgent=none", "StrictHostKeyChecking=yes",
        f"UserKnownHostsFile={hosts}", "GlobalKnownHostsFile=/dev/null", "PasswordAuthentication=no",
        "KbdInteractiveAuthentication=no", "ServerAliveInterval=30", "ServerAliveCountMax=3",
        "ConnectTimeout=15", "ControlMaster=no", "ControlPath=none", "LogLevel=ERROR"]
    command = shlex.join([source["python"], "-I", source["script"], "--source-stream"])
    return ["/usr/bin/ssh", "-F", "/dev/null", "-T", *[arg for option in options for arg in ("-o", option)],
            "-i", str(key), "-p", str(source["ssh_port"]), "--", f'{source["ssh_user"]}@{source["ssh_host"]}', command]


@contextmanager
def _source_process(contract: dict, relative: str | None):
    process = subprocess.Popen(_ssh_argv(contract["source"]), stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True,
        env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"})
    try:
        process.stdin.write(json.dumps(_source_request(contract, relative)).encode())
        process.stdin.close()
        yield process
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        if process.stdout:
            process.stdout.close()


def source_stream() -> int:
    """Read-only remote half. stdout is file bytes OR bounded verification JSON."""
    payload = sys.stdin.buffer.read(65537)
    if len(payload) > 65536:
        raise StageError("oversize source request")
    data = json.loads(payload)
    optional = {"max_entries"} if isinstance(data, dict) and "max_entries" in data else set()
    request = _closed(data, {"schema_version", "operation", "hostname", "root", "device",
        "inode", "census", "script_sha256", "manifest_sha256", "epoch", "relative"} | optional)
    with _envelope_bounds(_campaign_limit(request)):
        return _source_stream_request(request)


def _source_stream_request(request: dict) -> int:
    if request["schema_version"] != 1 or type(request["schema_version"]) is not int or request["epoch"] != "E0" or request["operation"] not in ("file", "verify"):
        raise StageError("invalid source operation")
    if socket.gethostname() != request["hostname"] or hashlib.sha256(Path(__file__).read_bytes()).hexdigest() != _sha(request["script_sha256"]):
        raise StageError("wrong source host or source implementation")
    envelope = private_json(_absolute(request["census"]), policy.MAX_BYTES + 65536)
    _manifest, receipt, files = _eligible(envelope)
    if receipt["manifest_sha256"] != _sha(request["manifest_sha256"]) or (receipt["root_device"], receipt["root_inode"]) != (request["device"], request["inode"]):
        raise StageError("wrong frozen source")
    root = _absolute(request["root"])
    fd = _root(root)
    opened = [fd]
    try:
        if (os.fstat(fd).st_dev, os.fstat(fd).st_ino) != (request["device"], request["inode"]):
            raise StageError("source root changed")
        if request["operation"] == "verify":
            if request["relative"] is not None:
                raise StageError("verification has no relative file")
            spec = importlib.util.spec_from_file_location("mba_stage_final_census", Path(__file__).parents[2] / "checks/mba-media-census.py")
            collector = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(collector)
            collector.policy.MAX_ITEMS = policy.MAX_ITEMS
            collector.policy.MAX_BYTES = policy.MAX_BYTES
            checked = collector.collect(root, "source", "E0", envelope["manifest"])
            if (checked["receipt"]["root_device"], checked["receipt"]["root_inode"]) != (request["device"], request["inode"]):
                raise StageError("source root changed during final verification")
            print(json.dumps({"manifest_sha256": checked["receipt"]["manifest_sha256"],
                              "eligible_files": len(files)}))
            return 0
        rows = {row["path"]: row for row in files}
        relative = request["relative"]
        if not isinstance(relative, str) or relative not in rows:
            raise StageError("unasserted source file")
        for part in relative.split("/")[:-1]:
            fd = _child(fd, part, request["device"])
            opened.append(fd)
        name = relative.split("/")[-1]
        before = os.stat(name, dir_fd=fd, follow_symlinks=False)
        _regular(before, request["device"])
        file_fd = os.open(name, READ, dir_fd=fd)
        opened.append(file_fd)
        if _stamp(os.fstat(file_fd)) != _stamp(before):
            raise StageError("source changed while opening")
        digest, count = hashlib.sha256(), 0
        while chunk := os.read(file_fd, CHUNK):
            count += len(chunk)
            if count > rows[relative]["size"]:
                raise StageError("source size changed")
            digest.update(chunk)
            sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()
        if (count != rows[relative]["size"] or digest.hexdigest() != rows[relative]["sha256"]
                or _stamp(os.fstat(file_fd)) != _stamp(before)
                or _stamp(os.stat(name, dir_fd=fd, follow_symlinks=False)) != _stamp(before)):
            raise StageError("source bytes or identity changed")
        current = _root(root)
        try:
            if (os.fstat(current).st_dev, os.fstat(current).st_ino) != (request["device"], request["inode"]):
                raise StageError("source root pathname changed")
        finally:
            os.close(current)
        return 0
    finally:
        for fd in reversed(opened):
            os.close(fd)


def _target_parent(root: int, relative: str, device: int) -> tuple[int, list[int]]:
    fd, opened = root, []
    for part in relative.split("/")[:-1]:
        fd = _directory(fd, part, device)
        opened.append(fd)
    return fd, opened


def _pin_directories(root: int, tree: int, journal: int, relative: str, directories: list[int]) -> None:
    for name, fd in ((UNSERVED, tree), (".journal", journal)):
        entry = os.stat(name, dir_fd=root, follow_symlinks=False)
        held = os.fstat(fd)
        if not stat.S_ISDIR(entry.st_mode) or (entry.st_dev, entry.st_ino) != (held.st_dev, held.st_ino):
            raise StageError("staging tree or journal pathname changed")
    parent = tree
    for name, fd in zip(relative.split("/")[:-1], directories, strict=True):
        entry = os.stat(name, dir_fd=parent, follow_symlinks=False)
        held = os.fstat(fd)
        if not stat.S_ISDIR(entry.st_mode) or (entry.st_dev, entry.st_ino) != (held.st_dev, held.st_ino):
            raise StageError("staging ancestor pathname changed")
        parent = fd


def _production_file(contract: dict, row: dict, target_fd: int, tree: int, journal: int,
                     remaining: int, max_file: int, fault=None) -> str:
    relative, device = row["path"], contract["target"]["device"]
    parent, opened = _target_parent(tree, relative, device)
    directories = list(opened)
    try:
        _pin_directories(target_fd, tree, journal, relative, directories)
        name = relative.split("/")[-1]
        record_id = hashlib.sha256(relative.encode()).hexdigest()
        record_name = record_id + ".json"
        base = {"path": relative, "manifest_sha256": contract["manifest_sha256"]}
        record = _read_journal(journal, record_name)
        attempt = 1
        if record is not None:
            if set(record) != {"path", "manifest_sha256", "attempt", "temp", "phase"} or any(record.get(k) != v for k, v in base.items()) or record["phase"] not in ("pre", "post"):
                raise StageError("production journal mismatch")
            attempt = _positive(record["attempt"])
            if record["temp"] != f".stage-{record_id}-{attempt}":
                raise StageError("production temp mismatch")
            if _entry_exists(parent, name):
                if _entry_exists(parent, record["temp"]):
                    raise StageError("ambiguous final and partial; retained")
                if not _check_existing(parent, name, row, device):
                    raise StageError("missing completed file")
                final = os.open(name, READ, dir_fd=parent)
                try:
                    _hash_fd(final, row, device)
                    _pin_directories(target_fd, tree, journal, relative, directories)
                    if _stamp(os.stat(name, dir_fd=parent, follow_symlinks=False)) != _stamp(os.fstat(final)):
                        raise StageError("completed pathname changed")
                    if record["phase"] == "pre":
                        _sync_json(journal, record_name, {**record, "phase": "post"}, replace=True)
                finally:
                    os.close(final)
                return "reused"
            if record["phase"] == "post":
                raise StageError("completed file vanished; no automatic replay")
            # Retain an interrupted partial under the control directory before
            # allocating a fresh single in-flight temp. Never unlink old bytes.
            retained = f".retained-{record_id}-{attempt}"
            if _entry_exists(parent, record["temp"]):
                partial = os.stat(record["temp"], dir_fd=parent, follow_symlinks=False)
                _regular(partial, device)
                if partial.st_size > row["size"]:
                    raise StageError("oversize interrupted partial")
                _rename_exclusive(parent, record["temp"], journal, retained)
                os.fsync(parent)
                os.fsync(journal)
            history = record_name + f".attempt-{attempt}"
            prior = _read_journal(journal, history)
            if prior is None:
                _sync_json(journal, history, record, replace=False)
            elif prior != record:
                raise StageError("interrupted history collision")
            attempt += 1
        elif _entry_exists(parent, name):
            raise StageError("unrecorded final collision")
        _capacity(target_fd, contract["target"], remaining + max_file)
        record = {**base, "attempt": attempt, "temp": f".stage-{record_id}-{attempt}", "phase": "pre"}
        _sync_json(journal, record_name, record, replace=attempt > 1)
        if fault:
            fault("after_pre")
        write_fd = os.open(record["temp"], CREATE, 0o600, dir_fd=parent)
        opened.append(write_fd)
        digest, count = hashlib.sha256(), 0
        with _source_process(contract, relative) as process:
            while chunk := process.stdout.read(min(CHUNK, row["size"] - count + 1)):
                count += len(chunk)
                if count > row["size"]:
                    raise StageError("source stream exceeded frozen size")
                view = memoryview(chunk)
                while view:
                    written = os.write(write_fd, view)
                    if written <= 0:
                        raise StageError("short target write")
                    view = view[written:]
                digest.update(chunk)
                _capacity(target_fd, contract["target"], max(0, remaining - count) + max_file)
                if fault:
                    fault("during_write")
            if process.wait() != 0 or count != row["size"] or digest.hexdigest() != row["sha256"]:
                raise StageError("source stream did not verify")
        os.fsync(write_fd)
        os.fsync(parent)
        _observe_target(contract["target"], target_fd)
        _capacity(target_fd, contract["target"], max(0, remaining - count) + max_file)
        if fault:
            fault("before_rename")
        _pin_directories(target_fd, tree, journal, relative, directories)
        if _stamp(os.stat(record["temp"], dir_fd=parent, follow_symlinks=False)) != _stamp(os.fstat(write_fd)):
            raise StageError("partial pathname changed")
        _rename_exclusive(parent, record["temp"], parent, name)
        os.fsync(parent)
        if fault:
            fault("after_rename")
        final = os.open(name, READ, dir_fd=parent)
        opened.append(final)
        if (os.fstat(final).st_dev, os.fstat(final).st_ino) != (os.fstat(write_fd).st_dev, os.fstat(write_fd).st_ino):
            raise StageError("promoted identity changed")
        _hash_fd(final, row, device)
        _pin_directories(target_fd, tree, journal, relative, directories)
        if _stamp(os.stat(name, dir_fd=parent, follow_symlinks=False)) != _stamp(os.fstat(final)):
            raise StageError("final pathname changed")
        _sync_json(journal, record_name, {**record, "phase": "post"}, replace=True)
        return "copied"
    finally:
        for fd in reversed(opened):
            os.close(fd)


def _verify_tree(tree: int, rows: list[dict], device: int) -> None:
    expected = {row["path"]: row for row in rows}
    seen = set()
    def visit(fd: int, prefix: str):
        before = os.fstat(fd)
        names = set(os.listdir(fd))
        for name in sorted(names):
            relative = f"{prefix}/{name}" if prefix else name
            entry = os.stat(name, dir_fd=fd, follow_symlinks=False)
            if stat.S_ISDIR(entry.st_mode):
                if not any(path.startswith(relative + "/") for path in expected):
                    raise StageError("unexpected staged directory")
                child = _child(fd, name, device)
                try:
                    visit(child, relative)
                    if _stamp(os.stat(name, dir_fd=fd, follow_symlinks=False)) != _stamp(os.fstat(child)):
                        raise StageError("readback directory pathname changed")
                finally:
                    os.close(child)
            elif relative in expected:
                child = os.open(name, READ, dir_fd=fd)
                try:
                    _hash_fd(child, expected[relative], device)
                    if _stamp(os.stat(name, dir_fd=fd, follow_symlinks=False)) != _stamp(os.fstat(child)):
                        raise StageError("readback pathname changed")
                finally:
                    os.close(child)
                seen.add(relative)
            else:
                raise StageError("unexpected staged entry")
        if set(os.listdir(fd)) != names or _stamp(os.fstat(fd)) != _stamp(before):
            raise StageError("staged directory changed during readback")
    visit(tree, "")
    if seen != set(expected):
        raise StageError("incomplete final staged set")


def stage_e0(contract: dict, envelope: dict, *, fault=None) -> dict:
    """Production target: additive serial SSH pull, durable resume, no publication."""
    manifest, receipt, rows = validate_contract(contract, envelope)
    root = _root(_absolute(contract["target"]["root"]))
    opened = [root]
    journal, run = None, None
    try:
        _owned_directory(root)
        _observe_target(contract["target"], root)
        # A first campaign can only adopt an empty private staging root.
        names = set(os.listdir(root))
        if names - {UNSERVED, ".journal"}:
            raise StageError("production root is not new staging")
        tree = _directory(root, UNSERVED, contract["target"]["device"])
        opened.append(tree)
        # Control/journal/retained failed bytes stay OUTSIDE the media tree so
        # a later independent census never needs an implicit hidden exclusion.
        journal = _directory(root, ".journal", contract["target"]["device"])
        opened.append(journal)
        lock = os.open(".stage.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600, dir_fd=journal)
        opened.append(lock)
        _regular(os.fstat(lock), contract["target"]["device"])
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise StageError("another production file is in flight") from exc
        frozen = {"contract_sha256": hashlib.sha256(json.dumps(contract, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
                  "campaign_id": contract["campaign_id"], "started_at": contract["started_at"],
                  "capacity_receipt_sha256": contract["capacity_receipt_sha256"]}
        current = _read_journal(journal, ".production.json")
        if current is None:
            if set(os.listdir(tree)) or set(os.listdir(journal)) != {".stage.lock"}:
                raise StageError("first campaign refuses pre-existing staged data")
            if datetime.now(timezone.utc) - _instant(contract["started_at"]) > timedelta(hours=1):
                raise StageError("first campaign must start with fresh start evidence")
            _capacity(root, contract["target"], sum(row["size"] for row in rows) + max(row["size"] for row in rows))
            _sync_json(journal, ".production.json", frozen, replace=False)
        elif current != frozen:
            raise StageError("staging belongs to another frozen production contract")
        _pin_cohort(journal, _cohort(manifest, receipt, os.fstat(root)), create=True)
        run = {"run_id": os.urandom(16).hex(), "status": "RUNNING", "campaign_id": contract["campaign_id"]}
        _sync_json(journal, ".run.json", run, replace=_entry_exists(journal, ".run.json"))
        remaining = sum(row["size"] for row in rows)
        maximum = max(row["size"] for row in rows)
        copied = reused = 0
        for row in rows:
            _observe_target(contract["target"], root)
            state = _production_file(contract, row, root, tree, journal, remaining, maximum, fault=fault)
            copied += state == "copied"
            reused += state == "reused"
            remaining -= row["size"]
        with _source_process(contract, None) as process:
            output = process.stdout.read(4097)
            if len(output) > 4096 or process.wait() != 0:
                raise StageError("final source census failed")
            if json.loads(output) != {"manifest_sha256": receipt["manifest_sha256"], "eligible_files": len(rows)}:
                raise StageError("final source census differs")
        _verify_tree(tree, rows, contract["target"]["device"])
        _pin_directories(root, tree, journal, "", [])
        if _read_journal(journal, ".production.json") != frozen:
            raise StageError("production contract pin changed during copy")
        _pin_cohort(journal, _cohort(manifest, receipt, os.fstat(root)), create=False)
        _observe_target(contract["target"], root)
        _capacity(root, contract["target"], 0)
        result = {"status": "E0_UNSERVED_VERIFIED", "campaign_id": contract["campaign_id"], "run_id": run["run_id"],
                  "manifest_sha256": receipt["manifest_sha256"], "files": len(rows),
                  "total_bytes": sum(row["size"] for row in rows), "publication": "forbidden"}
        _sync_json(journal, ".result.json", result, replace=_entry_exists(journal, ".result.json"))
        _sync_json(journal, ".run.json", {**run, "status": "VERIFIED"}, replace=True)
        return {**result, "copied_this_run": copied, "verified_reused_this_run": reused,
                "backup_or_E1_publication_proven": False}
    except BaseException:
        if run is not None:
            try:
                _sync_json(journal, ".run.json", {**run, "status": "INCOMPLETE"}, replace=True)
            except (OSError, ValueError):
                pass  # RUNNING is also incomplete; never fabricate completion.
        raise
    finally:
        for fd in reversed(opened):
            os.close(fd)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--census", type=Path, help="G2 source census envelope JSON")
    parser.add_argument("--dry-run", action="store_true", help="read-only eligible-set plan")
    parser.add_argument("--stage-e0", type=Path, help="private frozen production contract; E0 stays unserved")
    parser.add_argument("--source-stream", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--max-entries", type=int, help="whole-census limit, 1..100000; production must match frozen contract")
    args = parser.parse_args(argv)
    try:
        if args.source_stream:
            if args.census or args.dry_run or args.stage_e0 or args.max_entries is not None:
                raise StageError("source mode is exclusive")
            return source_stream()
        if args.stage_e0:
            if args.census is None or args.dry_run:
                raise StageError("production requires census and its explicit contract")
            def interrupted(_signum, _frame):
                raise InterruptedError("staging interrupted; retained journal")
            signal.signal(signal.SIGTERM, interrupted)
            signal.signal(signal.SIGINT, interrupted)
            contract = private_json(args.stage_e0, 65536)
            limit = _campaign_limit(contract)
            if args.max_entries is not None and _entry_limit(args.max_entries) != limit:
                raise StageError("entry limit differs from frozen campaign")
            with _envelope_bounds(limit):
                output = stage_e0(contract, private_json(args.census, policy.MAX_BYTES + 65536))
            print(json.dumps(output, sort_keys=True))
            return 0
        if args.census is None:
            raise StageError("census is required")
        with _envelope_bounds(_entry_limit(args.max_entries) if args.max_entries is not None else DEFAULT_MAX_ENTRIES):
            envelope = policy.read_document(args.census)
            output = plan(envelope)
    except (InterruptedError, KeyboardInterrupt):
        print("error: staging interrupted; private partials and journal retained", file=sys.stderr)
        return 130
    except (OSError, UnicodeError, ValueError, TypeError, RecursionError, KeyError):
        print("error: staging refused; inspect private contract/journal; no publication", file=sys.stderr)
        return 1
    print(json.dumps(output, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
