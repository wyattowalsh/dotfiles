#!/usr/bin/env python3
"""Stage review-required candidates from slskd's persisted completion events.

This adapter performs GET requests only and never imports, retags, moves, deletes,
or publishes music. A shared verifier/promoter must subsequently admit candidates.
The completion event supplies the actual filename after slskd's collision rename;
the transfer's Succeeded state alone precedes that move and is insufficient.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import stat
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

PAGE_LIMIT = 100
PAGE_BYTES = 4 * 1024 * 1024


def read_private(path: Path) -> dict:
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "r", encoding="utf-8") as source:
        st = os.fstat(source.fileno())
        if (
            not stat.S_ISREG(st.st_mode)
            or st.st_uid != os.getuid()
            or st.st_mode & 0o077
        ):
            raise ValueError("input must be an owned private regular file")
        return json.load(source)


def stamp(st: os.stat_result) -> dict:
    return {
        "dev": st.st_dev,
        "ino": st.st_ino,
        "size": st.st_size,
        "mtime_ns": st.st_mtime_ns,
        "ctime_ns": st.st_ctime_ns,
    }


def candidate(record: dict, completed: Path, settle_seconds: int = 30) -> dict | None:
    if not isinstance(record, dict):
        raise TypeError("event record must be an object")
    if record.get("type") != "DownloadFileComplete":
        return None
    data = json.loads(record["data"])
    if data.get("version") != 0:
        raise ValueError("unsupported completion-event version")
    event_id = str(uuid.UUID(record["id"]))
    transfer = data["transfer"]
    if not isinstance(transfer, dict) or not isinstance(transfer.get("state"), str):
        raise TypeError("invalid transfer payload")
    transfer_id = str(uuid.UUID(transfer["id"]))
    if event_id == str(uuid.UUID(int=0)) or transfer_id == str(uuid.UUID(int=0)):
        raise ValueError("completion/transfer identifier is empty")
    if transfer.get("direction") != "Download":
        raise ValueError("event is not a download")
    states = {part.strip() for part in transfer.get("state", "").split(",")}
    if states != {"Completed", "Succeeded"} or transfer.get("exception"):
        raise ValueError("transfer has not succeeded completely")
    if transfer.get("endedAt") is None or transfer.get("removed"):
        raise ValueError("completion metadata is incomplete or removed")
    if not transfer.get("username") or data.get("remoteFilename") != transfer.get(
        "filename"
    ):
        raise ValueError("peer/remote-filename binding is incomplete")
    size = transfer.get("size")
    if (
        not isinstance(size, int)
        or isinstance(size, bool)
        or size <= 0
        or transfer.get("bytesTransferred") != size
    ):
        raise ValueError("transfer byte counts do not match")
    root = completed.resolve(strict=True)
    path = Path(data["localFilename"])
    if not path.is_absolute() or not path.is_relative_to(root) or path == root:
        raise ValueError("completed file lies outside the exact inbox")
    if path.resolve(strict=True) != path:
        raise ValueError("symlinked completion paths are refused")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as source:
        before = os.fstat(source.fileno())
        if (
            not stat.S_ISREG(before.st_mode)
            or before.st_uid != os.getuid()
            or before.st_size != size
        ):
            raise ValueError("completed file ownership/type/size mismatch")
        if time.time_ns() - before.st_mtime_ns < settle_seconds * 1_000_000_000:
            raise ValueError("completed file is not settled")
        h = hashlib.sha256()
        for block in iter(lambda: source.read(1024 * 1024), b""):
            h.update(block)
        after = os.fstat(source.fileno())
    if stamp(before) != stamp(after) or stamp(
        path.stat(follow_symlinks=False)
    ) != stamp(after):
        raise ValueError("completed file changed during verification")
    return {
        "schema": 1,
        "candidate_id": "slskd-" + transfer_id,
        "source_kind": "slskd",
        "transfer_id": transfer_id,
        "event_id": event_id,
        "event_timestamp": record["timestamp"],
        "event_sha256": hashlib.sha256(
            json.dumps(record, sort_keys=True, separators=(",", ":")).encode()
        ).hexdigest(),
        "username": transfer["username"],
        "remote_path": transfer["filename"],
        "local_path": str(path),
        "file_size": size,
        "file_sha256": h.hexdigest(),
        "file_stamp": stamp(after),
        "identity_status": "review_required",
        "format_verified": False,
        "canonical_effects": False,
    }


def stage(item: dict, directory: Path) -> str:
    path = directory / (item["candidate_id"] + ".json")
    if path.exists() or path.is_symlink():
        old = read_private(path)
        keys = (
            "transfer_id",
            "username",
            "remote_path",
            "local_path",
            "file_size",
            "file_sha256",
        )
        if any(old.get(key) != item[key] for key in keys):
            raise ValueError("existing candidate conflicts; reconciliation required")
        return "reused"
    # Link a complete, fsynced private file to the immutable final name. A race
    # cannot overwrite another receipt; the caller holds the intake lease too.
    fd, temporary = tempfile.mkstemp(prefix=".candidate-", dir=directory)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as target:
            target.write((json.dumps(item, sort_keys=True, indent=2) + "\n").encode())
            target.flush()
            os.fsync(target.fileno())
        os.link(temporary, path, follow_symlinks=False)
    finally:
        os.unlink(temporary)
    return "staged"


def get_events(key: str, offset: int) -> list:
    request = urllib.request.Request(
        f"http://127.0.0.1:5030/api/v0/events?offset={offset}&limit={PAGE_LIMIT}",
        headers={"X-API-Key": key, "Accept": "application/json"},
        method="GET",
    )

    # No off-host redirect can receive the private key.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    with urllib.request.build_opener(NoRedirect).open(request, timeout=15) as response:
        data = response.read(PAGE_BYTES + 1)
    if len(data) > PAGE_BYTES:
        raise ValueError("event page exceeds its bounded response budget")
    records = json.loads(data)
    if not isinstance(records, list) or len(records) > PAGE_LIMIT:
        raise ValueError("unexpected event page shape")
    return records


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--state-dir", type=Path, default=Path.home() / ".local/share/slskd"
    )
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--pages", type=int, default=20)
    parser.add_argument("--offset", type=int, default=0)
    parser.add_argument("--settle-seconds", type=int, default=30)
    args = parser.parse_args()
    try:
        if not 1 <= args.pages <= 100 or args.offset < 0 or args.settle_seconds < 0:
            raise ValueError("invalid bounded scan settings")
        state = args.state_dir.resolve(strict=True)
        if args.state_dir.is_symlink():
            raise ValueError("state symlink refused")
        credentials = read_private(state / "credentials.private.json")
        directory = state / "candidates"
        st = directory.lstat()
        if (
            not stat.S_ISDIR(st.st_mode)
            or st.st_uid != os.getuid()
            or st.st_mode & 0o077
        ):
            raise ValueError("candidate directory must be owned and private")
        lock_path = state / ".intake.lock"
        fd = (
            os.open(lock_path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
            if args.apply
            else None
        )
        lock = os.fdopen(fd, "w") if fd is not None else None
        if lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        counts = {"staged": 0, "reused": 0, "eligible": 0, "held": 0, "events": 0}
        exhausted = False
        try:
            for page in range(args.pages):
                records = get_events(
                    credentials["intake_api_key"], args.offset + page * PAGE_LIMIT
                )
                for record in records:
                    counts["events"] += 1
                    try:
                        item = candidate(
                            record, state / "completed", args.settle_seconds
                        )
                        if item is not None:
                            counts["eligible"] += 1
                            if args.apply:
                                counts[stage(item, directory)] += 1
                    except (ValueError, KeyError, TypeError, OSError):
                        counts["held"] += 1
                if len(records) < PAGE_LIMIT:
                    exhausted = True
                    break
        finally:
            if lock:
                lock.close()
        print(
            json.dumps(
                {
                    "ok": counts["held"] == 0,
                    "apply": args.apply,
                    **counts,
                    "history_exhausted": exhausted,
                    "scan_may_be_incomplete": not exhausted,
                    "canonical_effects": False,
                    "identity_verified": False,
                },
                sort_keys=True,
            )
        )
        return 0 if counts["held"] == 0 else 2
    except (ValueError, OSError, KeyError, urllib.error.URLError) as exc:
        print(
            json.dumps(
                {
                    "ok": False,
                    "error_type": type(exc).__name__,
                    "canonical_effects": False,
                }
            )
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
