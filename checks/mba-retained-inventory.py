"""Source-only ST02/ST06 retained-root metadata census; never a backup or deletion gate.

CLI (explicit roots only; no discovery):
    gtimeout 8s uv run python -I checks/mba-retained-inventory.py \
      --max-seconds 5 --ack-soft-deadline --root /absolute/literal/root

Only directory descriptors are opened. File data, hashes, xattrs, cloud APIs,
backup repositories, and file-provider download operations are never requested.
The Python monotonic deadline is cooperative: a blocked macOS syscall (including
open/scandir/stat) can exceed it. The caller must separately supervise a real
host run with an external hard timeout such as gtimeout; the acknowledgement
flag explicitly does NOT implement one. No production root is implied or run.

All totals are observed metadata, not unique reclaimable APFS bytes. Snapshots,
clones, cross-root overlaps, cloud remote quota, and volume UUID are UNKNOWN.
Incomplete roots and aggregate receipts remain UNKNOWN; partial subtotals are
never promoted to a complete size or backup/retention proof. Output contains no
path, basename, account, error message, or timestamp; root_001 is input order.
"""

from __future__ import annotations

import argparse
import errno
import json
import os
import stat
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence

DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
MAX_ROOTS = 16
MAX_ENTRIES = 50_000
MAX_DEPTH = 64
MAX_SECONDS = 30.0


@dataclass(frozen=True)
class Limits:
    entries: int = 5_000
    depth: int = 24
    seconds: float = 5.0

    def validate(self) -> None:
        if not (1 <= self.entries <= MAX_ENTRIES and 1 <= self.depth <= MAX_DEPTH
                and 0 < self.seconds <= MAX_SECONDS):
            raise ValueError("invalid bounds")


class Incomplete(Exception):
    def __init__(self, reason: str, number: int | None = None):
        self.reason = reason
        self.number = number
        super().__init__(reason)


def open_root(raw: str | Path) -> int:
    """Reject even a symlinked ancestor; do not resolve or normalize the input."""
    path = os.fspath(raw)
    if not isinstance(path, str) or not path.startswith("/"):
        raise Incomplete("INVALID_ROOT")
    components = path[1:].split("/")
    if any(part in ("", ".", "..") for part in components):
        raise Incomplete("INVALID_ROOT")
    fd = os.open("/", DIR_FLAGS)
    try:
        for part in components:
            # Metadata preflight before opening any possibly dataless directory.
            # O_NOFOLLOW also enforces the no-symlink rule if the path races.
            if is_dataless(os.stat(part, dir_fd=fd, follow_symlinks=False)):
                raise Incomplete("DATALESS")
            child = os.open(part, DIR_FLAGS, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


def is_dataless(entry: os.stat_result) -> bool:
    return bool(getattr(entry, "st_flags", 0) & getattr(stat, "SF_DATALESS", 0))


def same_volume(entry: os.stat_result, device: int) -> bool:
    return entry.st_dev == device


def fingerprint(entry: os.stat_result) -> tuple[int, ...]:
    return (entry.st_dev, entry.st_ino, entry.st_mode, entry.st_size,
            entry.st_mtime_ns, entry.st_ctime_ns, getattr(entry, "st_flags", 0),
            getattr(entry, "st_blocks", -1))


def scan_names(fd: int, remaining: int, tick: Callable[[], None]) -> list[str]:
    names: list[str] = []
    with os.scandir(fd) as stream:
        for entry in stream:
            tick()
            if len(names) >= remaining:
                raise Incomplete("ENTRY_LIMIT")
            names.append(entry.name)
    if len(names) != len(set(names)):
        raise Incomplete("UNSTABLE_LISTING")
    return sorted(names)


def empty_root(index: int) -> dict[str, object]:
    return {
        "id": f"root_{index:03d}", "status": "UNKNOWN", "root_identity": None,
        "volume_identity": None, "entries_observed": 0, "objects_counted": 0,
        "logical_bytes_observed": 0, "allocated_bytes_observed": 0,
        "issue": None,
    }


def census_root(raw: str | Path, index: int, limits: Limits,
                tick: Callable[[], None]) -> dict[str, object]:
    row = empty_root(index)
    seen: set[tuple[int, int]] = set()  # hardlinks are counted once per root
    root_fd: int | None = None
    try:
        tick()
        root_fd = open_root(raw)
        root_stat = os.fstat(root_fd)
        if not stat.S_ISDIR(root_stat.st_mode):
            raise Incomplete("UNSUPPORTED_ENTRY")
        row["root_identity"] = {"device": root_stat.st_dev, "inode": root_stat.st_ino}
        row["volume_identity"] = {"kind": "st_dev_only", "device": root_stat.st_dev,
                                  "apfs_volume_uuid": "UNKNOWN", "container": "UNKNOWN"}
        device = root_stat.st_dev

        def account(entry: os.stat_result) -> None:
            tick()
            if not same_volume(entry, device):
                raise Incomplete("VOLUME_SWITCH", errno.EXDEV)
            if is_dataless(entry):
                raise Incomplete("DATALESS")
            if not (stat.S_ISDIR(entry.st_mode) or stat.S_ISREG(entry.st_mode)):
                raise Incomplete("UNSUPPORTED_ENTRY")
            blocks = getattr(entry, "st_blocks", None)
            if (entry.st_size < 0 or blocks is None or blocks < 0
                    or (stat.S_ISREG(entry.st_mode) and entry.st_size > 0 and blocks == 0)):
                raise Incomplete("ALLOCATED_UNKNOWN")
            identity = (entry.st_dev, entry.st_ino)
            if identity not in seen:
                seen.add(identity)
                row["logical_bytes_observed"] += entry.st_size
                row["allocated_bytes_observed"] += blocks * 512
                row["objects_counted"] += 1

        account(root_stat)

        def walk(fd: int, expected: os.stat_result, depth: int) -> None:
            tick()
            before = os.fstat(fd)
            if fingerprint(before) != fingerprint(expected):
                raise Incomplete("METADATA_DRIFT")
            remaining = limits.entries - int(row["entries_observed"])
            # A full budget still permits an empty directory; its first child
            # will trip ENTRY_LIMIT before any child metadata is counted.
            names = scan_names(fd, remaining, tick)
            for name in names:
                tick()
                row["entries_observed"] += 1
                child = os.stat(name, dir_fd=fd, follow_symlinks=False)
                if stat.S_ISLNK(child.st_mode):
                    raise Incomplete("SYMLINK")
                account(child)
                if stat.S_ISDIR(child.st_mode):
                    if depth >= limits.depth:
                        raise Incomplete("DEPTH_LIMIT")
                    child_fd = os.open(name, DIR_FLAGS, dir_fd=fd)
                    try:
                        if fingerprint(os.fstat(child_fd)) != fingerprint(child):
                            raise Incomplete("METADATA_DRIFT")
                        walk(child_fd, child, depth + 1)
                        if fingerprint(os.fstat(child_fd)) != fingerprint(child):
                            raise Incomplete("METADATA_DRIFT")
                    finally:
                        os.close(child_fd)
                # Recheck each child path without following a swapped-in link.
                if fingerprint(os.stat(name, dir_fd=fd, follow_symlinks=False)) != fingerprint(child):
                    raise Incomplete("METADATA_DRIFT")
            if fingerprint(os.fstat(fd)) != fingerprint(before):
                raise Incomplete("METADATA_DRIFT")

        walk(root_fd, root_stat, 0)
        tick()
        # A renamed/replaced root descriptor is not proof about the input path.
        reopened = open_root(raw)
        try:
            if fingerprint(os.fstat(reopened)) != fingerprint(root_stat):
                raise Incomplete("METADATA_DRIFT")
        finally:
            os.close(reopened)
        row["status"] = "complete"
    except Incomplete as failure:
        row["issue"] = {"reason": failure.reason, "errno": failure.number}
    except OSError as failure:
        row["issue"] = {"reason": "OS_ERROR", "errno": failure.errno}
    finally:
        if root_fd is not None:
            try:
                os.close(root_fd)
            except OSError as failure:
                row["status"] = "UNKNOWN"
                row["issue"] = {"reason": "OS_ERROR", "errno": failure.errno}
    return row


def collect(roots: Sequence[str | Path], limits: Limits = Limits(),
            *, clock: Callable[[], float] = time.monotonic) -> dict[str, object]:
    """Bounded metadata observation; each input is one explicit literal root."""
    limits.validate()
    if not (1 <= len(roots) <= MAX_ROOTS):
        raise ValueError("invalid root count")
    rows = []
    for index, raw in enumerate(roots, 1):
        deadline = clock() + limits.seconds

        def tick() -> None:
            if clock() >= deadline:
                raise Incomplete("DEADLINE")

        rows.append(census_root(raw, index, limits, tick))
    complete = all(row["status"] == "complete" for row in rows)
    # Cross-root inode overlap means even complete per-root subtotals cannot be
    # summed as distinct objects. No aggregate allocated/reclaimable total.
    return {
        "schema_version": 1, "status": "complete" if complete else "UNKNOWN",
        "scope": "metadata_only_local_observation", "hard_syscall_timeout": False,
        "limits": {"max_roots": MAX_ROOTS, "max_entries_per_root": limits.entries,
                   "max_depth": limits.depth, "soft_seconds": limits.seconds},
        "aggregate": {"status": "UNKNOWN", "reason": "CROSS_ROOT_OVERLAP_AND_CLOUD_UNKNOWN"
                      if complete else "INCOMPLETE_ROOT_AND_OVERLAP_UNKNOWN",
                      "reclaimable_bytes": "UNKNOWN", "unique_allocated_bytes": "UNKNOWN",
                      "cloud_remote_bytes": "UNKNOWN", "snapshots_and_clones": "UNKNOWN"},
        "roots": rows,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", action="append", required=True,
                        help="explicit literal absolute retained root (repeatable; never printed)")
    parser.add_argument("--max-entries", type=int, default=Limits.entries)
    parser.add_argument("--max-depth", type=int, default=Limits.depth)
    parser.add_argument("--max-seconds", type=float, default=Limits.seconds)
    parser.add_argument("--ack-soft-deadline", action="store_true", required=True,
                        help="acknowledge that an external hard timeout is required for host runs")
    args = parser.parse_args(argv)
    try:
        result = collect(args.root, Limits(args.max_entries, args.max_depth, args.max_seconds))
    except ValueError:
        print("error: invalid census limits or root count", file=sys.stderr)
        return 2
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0 if result["status"] == "complete" else 1


if __name__ == "__main__":
    raise SystemExit(main())
