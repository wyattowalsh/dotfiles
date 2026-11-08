"""Bounded MBA-local, review-only private file-level metadata manifest.

Example (a real host run MUST have an independent external hard timeout):
    gtimeout 8s uv run --offline --no-project python -I checks/mba-offload-manifest.py \
      --ack-soft-deadline --class-id protected_local --root /literal/private/root \
      --output-dir /preexisting/private/directory --output-name review.json

Only directory descriptors and a newly created output are opened. No regular-file
body, xattr, cloud provider, transfer, hydration, or deletion is requested.
The cooperative monotonic deadline cannot interrupt a blocked kernel syscall.
A complete manifest proves neither backup nor unique/reclaimable physical bytes.
The repeated scans are not an atomic snapshot; concurrent writes after the last
check remain possible. A failed output write may leave a private incomplete file;
never trust it without a complete matching receipt, and never automatically unlink
an exposed name that another process could replace. Run separately for each class.
"""
from __future__ import annotations

import argparse
import ctypes
import errno
import hashlib
import json
import os
import re
import stat
import sys
import time
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence

CLASSES = frozenset({"neo4j_app_state", "protected_local", "downloads_unknown", "model_cache"})
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
MAX_ROOTS = 8
MAX_ENTRIES = 50_000
MAX_DEPTH = 64
MAX_SECONDS = 30.0
MAX_MANIFEST_BYTES = 16_000_000


@dataclass(frozen=True)
class Limits:
    entries: int = 5_000
    depth: int = 24
    seconds: float = 5.0
    manifest_bytes: int = 2_000_000

    def validate(self) -> None:
        if not (1 <= self.entries <= MAX_ENTRIES and 0 <= self.depth <= MAX_DEPTH
                and 0 < self.seconds <= MAX_SECONDS
                and 1 <= self.manifest_bytes <= MAX_MANIFEST_BYTES):
            raise Incomplete("INVALID_LIMIT")


class Incomplete(Exception):
    def __init__(self, reason: str):
        self.reason = reason
        super().__init__(reason)


def components(raw: str | Path) -> tuple[str, ...]:
    path = os.fspath(raw)
    if not isinstance(path, str) or not path.startswith("/"):
        raise Incomplete("INVALID_ROOT")
    parts = tuple(path[1:].split("/"))
    if not parts or any(part in ("", ".", "..") for part in parts):
        raise Incomplete("INVALID_ROOT")
    return parts


def open_root(raw: str | Path, *, identities: list[tuple[int, int]] | None = None) -> int:
    """Walk literal components using pinned directory FDs; reject symlink ancestors."""
    fd = os.open("/", DIR_FLAGS)
    try:
        for part in components(raw):
            entry = os.stat(part, dir_fd=fd, follow_symlinks=False)
            if stat.S_ISLNK(entry.st_mode):
                raise Incomplete("SYMLINK")
            if is_dataless(entry):
                raise Incomplete("DATALESS")
            if not stat.S_ISDIR(entry.st_mode):
                raise Incomplete("UNSUPPORTED_ENTRY")
            try:
                child = os.open(part, DIR_FLAGS, dir_fd=fd)
            except OSError as error:
                if error.errno == errno.ELOOP:
                    raise Incomplete("SYMLINK") from error
                raise
            if fingerprint(os.fstat(child)) != fingerprint(entry):
                os.close(child)
                raise Incomplete("METADATA_DRIFT")
            if identities is not None:
                identities.append((entry.st_dev, entry.st_ino))
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


def directory_chain(raw: str | Path) -> tuple[tuple[int, int], ...]:
    identities: list[tuple[int, int]] = []
    fd = open_root(raw, identities=identities)
    try:
        return tuple(identities)
    finally:
        os.close(fd)


def chains_overlap(first: tuple[tuple[int, int], ...],
                   second: tuple[tuple[int, int], ...]) -> bool:
    return first[:len(second)] == second or second[:len(first)] == first


def output_matches(fd: int, name: str, created_fd: int) -> bool:
    try:
        entry = os.stat(name, dir_fd=fd, follow_symlinks=False)
    except FileNotFoundError:
        return False
    created = os.fstat(created_fd)
    return (entry.st_dev, entry.st_ino) == (created.st_dev, created.st_ino)


def output_acl_absent(fd: int) -> bool:
    """Require no macOS extended ACL on the pinned descriptor (not a pathname).

    sys/acl.h defines ACL_TYPE_EXTENDED as 0x100. On an ACL-free fd,
    acl_get_fd_np returns NULL with ENOENT; any returned ACL is rejected.
    Other NULL errors, including unsupported inspection, fail closed.
    """
    if sys.platform != "darwin":
        return True
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        get_acl = libc.acl_get_fd_np
        get_acl.argtypes = (ctypes.c_int, ctypes.c_int)
        get_acl.restype = ctypes.c_void_p
        free_acl = libc.acl_free
        free_acl.argtypes = (ctypes.c_void_p,)
        free_acl.restype = ctypes.c_int
        ctypes.set_errno(0)
        acl = get_acl(fd, 0x100)
        if not acl:
            if ctypes.get_errno() == errno.ENOENT:
                return True
            raise Incomplete("OUTPUT_PRIVACY")
        if free_acl(acl) != 0:
            raise Incomplete("OUTPUT_PRIVACY")
        return False
    except (
        AttributeError,
        OSError,
        TypeError,
        ValueError,
        ctypes.ArgumentError,
    ) as error:
        raise Incomplete("OUTPUT_PRIVACY") from error


def output_private(fd: int) -> bool:
    entry = os.fstat(fd)
    return (
        entry.st_uid == os.getuid()
        and stat.S_IMODE(entry.st_mode) == 0o700
        and output_acl_absent(fd)
    )


def output_file_private(fd: int) -> bool:
    entry = os.fstat(fd)
    return (
        entry.st_uid == os.getuid()
        and stat.S_IMODE(entry.st_mode) == 0o600
        and output_acl_absent(fd)
    )


def output_content_matches(fd: int, payload: bytes) -> bool:
    entry = os.fstat(fd)
    return (entry.st_uid == os.getuid() and stat.S_IMODE(entry.st_mode) == 0o600
            and entry.st_size == len(payload)
            and os.pread(fd, len(payload) + 1, 0) == payload)


def is_dataless(entry: os.stat_result) -> bool:
    return bool(getattr(entry, "st_flags", 0) & getattr(stat, "SF_DATALESS", 0))


def fingerprint(entry: os.stat_result) -> tuple[int, ...]:
    return (entry.st_dev, entry.st_ino, entry.st_nlink, entry.st_mode,
            entry.st_uid, entry.st_gid, entry.st_size,
            getattr(entry, "st_blocks", -1), getattr(entry, "st_flags", 0),
            entry.st_mtime_ns, entry.st_ctime_ns)


def metadata(entry: os.stat_result, relative_name: str, root_id: str, device: int) -> dict[str, object]:
    if entry.st_dev != device:
        raise Incomplete("VOLUME_SWITCH")
    if is_dataless(entry):
        raise Incomplete("DATALESS")
    if not (stat.S_ISDIR(entry.st_mode) or stat.S_ISREG(entry.st_mode)):
        raise Incomplete("SYMLINK" if stat.S_ISLNK(entry.st_mode) else "UNSUPPORTED_ENTRY")
    if entry.st_uid != os.getuid():
        raise Incomplete("SOURCE_OWNERSHIP")
    if stat.S_ISREG(entry.st_mode) and entry.st_nlink != 1:
        raise Incomplete("HARDLINK")
    blocks = getattr(entry, "st_blocks", None)
    if (entry.st_size < 0 or blocks is None or blocks < 0
            or (stat.S_ISREG(entry.st_mode) and entry.st_size > 0 and blocks == 0)):
        raise Incomplete("ALLOCATED_UNKNOWN")
    return {"root_id": root_id, "relative_name": relative_name,
            "device": entry.st_dev, "inode": entry.st_ino, "nlink": entry.st_nlink,
            "mode": entry.st_mode, "uid": entry.st_uid, "gid": entry.st_gid,
            "flags": getattr(entry, "st_flags", 0), "size": entry.st_size,
            "blocks": blocks, "mtime_ns": entry.st_mtime_ns,
            "ctime_ns": entry.st_ctime_ns}


def scan_names(fd: int, remaining: int, tick: Callable[[], None]) -> list[str]:
    names: list[str] = []
    with os.scandir(fd) as stream:
        for item in stream:
            tick()
            if len(names) >= remaining:
                raise Incomplete("ENTRY_LIMIT")
            name = item.name
            if (not name or "/" in name or any(
                    ord(character) < 32 or ord(character) == 127
                    or unicodedata.category(character) == "Cf" for character in name)):
                raise Incomplete("UNSAFE_NAME")
            names.append(name)
    return sorted(names)


def scan_root(raw: str | Path, root_id: str, limits: Limits,
              tick: Callable[[], None], remaining: int | None = None) -> list[dict[str, object]]:
    tick()
    fd = open_root(raw)
    try:
        root_stat = os.fstat(fd)
        rows = [metadata(root_stat, "", root_id, root_stat.st_dev)]
        device = root_stat.st_dev
        count = 0
        budget = limits.entries if remaining is None else remaining

        def walk(dir_fd: int, expected: os.stat_result, prefix: str, depth: int) -> None:
            nonlocal count
            tick()
            if fingerprint(os.fstat(dir_fd)) != fingerprint(expected):
                raise Incomplete("METADATA_DRIFT")
            names = scan_names(dir_fd, budget - count, tick)
            seen_names: set[str] = set()
            for name in names:
                tick()
                key = unicodedata.normalize("NFKC", name).casefold()
                if key in seen_names:
                    raise Incomplete("NAME_COLLISION")
                seen_names.add(key)
            for name in names:
                tick()
                count += 1
                child = os.stat(name, dir_fd=dir_fd, follow_symlinks=False)
                relative = prefix + name
                rows.append(metadata(child, relative, root_id, device))
                if stat.S_ISDIR(child.st_mode):
                    if depth >= limits.depth:
                        raise Incomplete("DEPTH_LIMIT")
                    child_fd = os.open(name, DIR_FLAGS, dir_fd=dir_fd)
                    try:
                        if fingerprint(os.fstat(child_fd)) != fingerprint(child):
                            raise Incomplete("METADATA_DRIFT")
                        walk(child_fd, child, relative + "/", depth + 1)
                        if fingerprint(os.fstat(child_fd)) != fingerprint(child):
                            raise Incomplete("METADATA_DRIFT")
                    finally:
                        os.close(child_fd)
                if fingerprint(os.stat(name, dir_fd=dir_fd, follow_symlinks=False)) != fingerprint(child):
                    raise Incomplete("METADATA_DRIFT")
            if fingerprint(os.fstat(dir_fd)) != fingerprint(expected):
                raise Incomplete("METADATA_DRIFT")

        walk(fd, root_stat, "", 0)
        tick()
        if fingerprint(os.fstat(fd)) != fingerprint(root_stat):
            raise Incomplete("METADATA_DRIFT")
        return rows
    finally:
        os.close(fd)


def canonical(document: dict[str, object], maximum: int) -> bytes:
    raw = json.dumps(document, sort_keys=True, ensure_ascii=True,
                     separators=(",", ":")).encode("utf-8") + b"\n"
    if len(raw) > maximum:
        raise Incomplete("MANIFEST_LIMIT")
    return raw


def receipt(class_id: str) -> dict[str, object]:
    return {"schema_version": 1, "status": "UNKNOWN", "reason": None,
            "class_id": class_id if class_id in CLASSES else "UNKNOWN",
            "roots": 0, "files": 0, "directories": 0,
            "logical_bytes_observed": 0, "allocated_bytes_observed": 0,
            "sha256": None, "review_only": True, "reclaim_credit_bytes": 0,
            "cross_class_overlap": "UNKNOWN", "transfer_eligible": False,
            "eviction_eligible": False,
            "hard_syscall_timeout": False, "atomic_snapshot": False,
            "incomplete_output_may_remain": False}


def collect(roots: Sequence[str | Path], class_id: str, output_dir: str | Path,
            output_name: str, limits: Limits = Limits(),
            *, clock: Callable[[], float] = time.monotonic) -> dict[str, object]:
    """Report complete only after bounded repeated scans and output readback."""
    public = receipt(class_id)
    out_fd: int | None = None
    try:
        limits.validate()
        if class_id not in CLASSES:
            raise Incomplete("INVALID_CLASS")
        if not 1 <= len(roots) <= MAX_ROOTS:
            raise Incomplete("INVALID_ROOT")
        if not isinstance(output_name, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", output_name):
            raise Incomplete("INVALID_OUTPUT")
        parts = [components(root) for root in roots]
        for index, first in enumerate(parts):
            for second in parts[:index]:
                if first[:len(second)] == second or second[:len(first)] == first:
                    raise Incomplete("ROOT_OVERLAP")
        try:
            output_parts = components(output_dir)
        except Incomplete as error:
            raise Incomplete("INVALID_OUTPUT") from error
        if any(root[:len(output_parts)] == output_parts or
               output_parts[:len(root)] == root for root in parts):
            raise Incomplete("OUTPUT_OVERLAP")
        deadline = clock() + limits.seconds

        def tick() -> None:
            if clock() >= deadline:
                raise Incomplete("DEADLINE")

        tick()
        root_chains = [directory_chain(root) for root in roots]
        output_chain: list[tuple[int, int]] = []
        out_fd = open_root(output_dir, identities=output_chain)
        for index, first in enumerate(root_chains):
            if chains_overlap(first, tuple(output_chain)):
                raise Incomplete("OUTPUT_OVERLAP")
            if any(chains_overlap(first, second) for second in root_chains[:index]):
                raise Incomplete("ROOT_OVERLAP")
        if not output_private(out_fd):
            raise Incomplete("OUTPUT_PRIVACY")
        try:
            os.stat(output_name, dir_fd=out_fd, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise Incomplete("OUTPUT_EXISTS")

        passes: list[list[dict[str, object]]] = []
        for _ in range(3):
            all_entries: list[dict[str, object]] = []
            observed = 0
            for index, root in enumerate(roots, 1):
                tick()
                found = scan_root(root, f"root_{index:03d}", limits, tick,
                                  limits.entries - observed)
                observed += len(found) - 1
                all_entries.extend(found)
                # Bound metadata buffering even before full serialization.
                canonical({"entries": all_entries}, limits.manifest_bytes)
            passes.append(all_entries)
        if passes[0] != passes[1] or passes[1] != passes[2]:
            raise Incomplete("METADATA_DRIFT")
        rows = passes[2]
        root_rows = [row for row in rows if row["relative_name"] == ""]
        if len({(row["device"], row["inode"]) for row in root_rows}) != len(roots):
            raise Incomplete("ROOT_OVERLAP")
        # A path replaced after pass two is not the manifest's pinned source.
        for index, root in enumerate(roots):
            tick()
            root_fd = open_root(root)
            try:
                if fingerprint(os.fstat(root_fd)) != tuple(root_rows[index][key] for key in (
                    "device", "inode", "nlink", "mode", "uid", "gid", "size", "blocks",
                    "flags", "mtime_ns", "ctime_ns")):
                    raise Incomplete("METADATA_DRIFT")
            finally:
                os.close(root_fd)
            if directory_chain(root) != root_chains[index]:
                raise Incomplete("METADATA_DRIFT")
        if directory_chain(output_dir) != tuple(output_chain):
            raise Incomplete("OUTPUT_DRIFT")
        if not output_private(out_fd):
            raise Incomplete("OUTPUT_PRIVACY")
        document = {"schema_version": 1, "scope": "metadata_only_local_review",
                    "class_id": class_id, "review_only": True,
                    "reclaim_credit_bytes": 0, "cross_class_overlap": "UNKNOWN",
                    "transfer_eligible": False, "eviction_eligible": False,
                    "hard_syscall_timeout": False, "atomic_snapshot": False,
                    "volume_identity": "st_dev_only_apfs_uuid_UNKNOWN",
                    "roots": [{"id": row["root_id"], "literal_root": os.fspath(roots[index]),
                               "device": row["device"], "inode": row["inode"]}
                              for index, row in enumerate(root_rows)],
                    "limits": {"entries": limits.entries, "depth": limits.depth,
                               "seconds": limits.seconds, "manifest_bytes": limits.manifest_bytes},
                    "entries": rows}
        payload = canonical(document, limits.manifest_bytes)
        tick()
        fd: int | None = None
        try:
            fd = os.open(output_name, os.O_RDWR | os.O_CREAT | os.O_EXCL |
                         os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0), 0o600, dir_fd=out_fd)
            public["incomplete_output_may_remain"] = True
            os.fchmod(fd, 0o600)
            if not output_file_private(fd) or not output_private(out_fd):
                raise Incomplete("OUTPUT_PRIVACY")
            write_fd = os.dup(fd)
            try:
                with os.fdopen(write_fd, "wb") as output:
                    output.write(payload)
                    output.flush()
                    os.fsync(output.fileno())
            except BaseException:
                try:
                    os.close(write_fd)
                except OSError:
                    pass
                raise
            if not output_matches(out_fd, output_name, fd):
                raise Incomplete("OUTPUT_DRIFT")
            os.fsync(out_fd)
            if not output_private(out_fd) or not output_file_private(fd):
                raise Incomplete("OUTPUT_PRIVACY")
            if (directory_chain(output_dir) != tuple(output_chain)
                    or not output_matches(out_fd, output_name, fd)
                    or not output_content_matches(fd, payload)):
                raise Incomplete("OUTPUT_DRIFT")
        except BaseException:
            if fd is not None and not output_matches(out_fd, output_name, fd):
                raise Incomplete("OUTPUT_DRIFT")
            raise
        finally:
            if fd is not None:
                os.close(fd)
        files = sum(stat.S_ISREG(row["mode"]) for row in rows)
        directories = sum(stat.S_ISDIR(row["mode"]) for row in rows)
        logical_bytes = sum(row["size"] for row in rows if stat.S_ISREG(row["mode"]))
        allocated_bytes = sum(row["blocks"] * 512 for row in rows if stat.S_ISREG(row["mode"]))
        digest = hashlib.sha256(payload).hexdigest()
        tick()
        public.update(status="complete", reason=None, roots=len(roots),
                      files=files, directories=directories,
                      logical_bytes_observed=logical_bytes,
                      allocated_bytes_observed=allocated_bytes, sha256=digest,
                      incomplete_output_may_remain=False)
    except Incomplete as error:
        public["reason"] = error.reason
    except OSError as error:
        public["reason"] = "OUTPUT_EXISTS" if error.errno == 17 else "OS_ERROR"
    finally:
        if out_fd is not None:
            try:
                os.close(out_fd)
            except OSError:
                public.update(status="UNKNOWN", reason="OS_ERROR", sha256=None,
                              incomplete_output_may_remain=True)
            else:
                if public["status"] == "complete" and clock() >= deadline:
                    public.update(status="UNKNOWN", reason="DEADLINE", sha256=None,
                                  incomplete_output_may_remain=True)
    return public


class RedactedParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        self.exit(2, "error: INVALID_ARGUMENT\n")


def main(argv: list[str] | None = None) -> int:
    parser = RedactedParser(description=__doc__, add_help=True)
    parser.add_argument("--class-id", required=True)
    parser.add_argument("--root", action="append", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--output-name", required=True)
    parser.add_argument("--max-entries", type=int, default=Limits.entries)
    parser.add_argument("--max-depth", type=int, default=Limits.depth)
    parser.add_argument("--max-seconds", type=float, default=Limits.seconds)
    parser.add_argument("--max-manifest-bytes", type=int, default=Limits.manifest_bytes)
    parser.add_argument("--ack-soft-deadline", action="store_true")
    args = parser.parse_args(argv)
    if not args.ack_soft_deadline:
        print("error: ACK_SOFT_DEADLINE_REQUIRED_EXTERNAL_HARD_TIMEOUT", file=sys.stderr)
        return 2
    result = collect(args.root, args.class_id, args.output_dir, args.output_name,
                     Limits(args.max_entries, args.max_depth, args.max_seconds,
                            args.max_manifest_bytes))
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0 if result["status"] == "complete" else 1


if __name__ == "__main__":
    raise SystemExit(main())
