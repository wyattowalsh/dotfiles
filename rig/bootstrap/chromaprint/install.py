#!/usr/bin/env python3
"""Preview/install one prepared native MBA fpcalc archive; never download or execute."""

import argparse
import gzip
import hashlib
import io
import json
import os
import platform
import pwd
import re
import shutil
import socket
import stat
import tarfile
from pathlib import Path

PIN = Path(__file__).resolve().parents[2] / "brew/chromaprint-pin.json"
GIB, MAX_BYTES = 1024**3, 4 * 1024**2


def need(ok, message):
    if not ok:
        raise ValueError(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def read(path, mode):
    before = path.lstat()
    need(
        path.is_absolute()
        and path.resolve(strict=True) == path
        and stat.S_ISREG(before.st_mode)
        and before.st_uid == os.getuid()
        and before.st_nlink == 1
        and stat.S_IMODE(before.st_mode) == mode
        and 0 < before.st_size <= MAX_BYTES
        and not getattr(before, "st_flags", 0) & 0x40000000,
        "owned materialized regular file required",
    )
    fields = (
        "st_dev",
        "st_ino",
        "st_size",
        "st_mtime_ns",
        "st_ctime_ns",
        "st_mode",
        "st_uid",
        "st_nlink",
    )
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), "rb") as stream:
        raw = stream.read(MAX_BYTES + 1)
        need(
            len(raw) == before.st_size
            and all(
                getattr(s, k) == getattr(before, k)
                for s in (os.fstat(stream.fileno()), path.lstat())
                for k in fields
            ),
            "file changed during read",
        )
    return raw


def checked_archive(archive, pin):
    need(
        pin["name"] == "chromaprint" and re.fullmatch(r"\d+\.\d+\.\d+", pin["version"]),
        "invalid release pin",
    )
    p = pin["darwin_arm64"]
    need(
        p["binary_member"]
        == "chromaprint-fpcalc-" + pin["version"] + "-macos-arm64/fpcalc",
        "invalid member pin",
    )
    raw = read(archive, 0o600)
    need(len(raw) == p["bytes"] and digest(raw) == p["sha256"], "archive pin mismatch")
    with gzip.GzipFile(fileobj=io.BytesIO(raw)) as compressed:
        expanded = compressed.read(MAX_BYTES + 1)
    need(len(expanded) <= MAX_BYTES, "expanded archive exceeds bound")
    with tarfile.open(fileobj=io.BytesIO(expanded), mode="r:") as source:
        members = source.getmembers()
        root = p["binary_member"].rsplit("/", 1)[0]
        need(
            len(members) == 2
            and {m.name for m in members} == {root, p["binary_member"]},
            "unexpected archive members",
        )
        directory, binary = source.getmember(root), source.getmember(p["binary_member"])
        need(
            directory.isdir()
            and directory.size == 0
            and directory.mode == 0o755
            and binary.type in (tarfile.REGTYPE, tarfile.AREGTYPE)
            and binary.mode == 0o755
            and binary.size == p["binary_bytes"] <= MAX_BYTES,
            "invalid archive member type, mode or size",
        )
        with source.extractfile(binary) as stream:
            payload = stream.read(MAX_BYTES + 1)
    need(
        len(payload) == p["binary_bytes"]
        and digest(payload) == p["binary_sha256"]
        and payload[:8] == bytes.fromhex("cffaedfe0c000001"),
        "native arm64 binary pin mismatch",
    )
    return payload


def owned_directory(path, private=False):
    info = path.lstat()
    need(
        path.resolve(strict=True) == path
        and stat.S_ISDIR(info.st_mode)
        and info.st_uid == os.getuid()
        and not info.st_mode & 0o022
        and (not private or stat.S_IMODE(info.st_mode) == 0o700),
        "unsafe installation directory",
    )


def write_new(path, payload, mode):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
    with os.fdopen(fd, "wb") as output:
        output.write(payload)
        output.flush()
        os.fsync(output.fileno())


def install(archive, pin, home, apply=False):
    need(
        os.getuid() != 0
        and platform.system() == "Darwin"
        and platform.machine() == "arm64"
        and socket.gethostname().split(".")[0] == "MacBookAir"
        and home.is_absolute()
        and Path(pwd.getpwuid(os.getuid()).pw_dir) == home,
        "MBA normal-account home required",
    )
    owned_directory(home)
    payload = checked_archive(archive, pin)
    target = home / ".local/share/mba-music-tools/chromaprint/versions" / pin["version"]
    receipt = {
        "schema": 1,
        "version": pin["version"],
        "archive_sha256": pin["darwin_arm64"]["sha256"],
        "binary_sha256": digest(payload),
        "binary_bytes": len(payload),
        "runtime_verified": False,
    }
    encoded = (json.dumps(receipt, indent=2, sort_keys=True) + "\n").encode()
    parent = home
    for component in target.relative_to(home).parts[:-1]:
        parent /= component
        if os.path.lexists(parent):
            owned_directory(
                parent,
                private=parent.is_relative_to(home / ".local/share/mba-music-tools"),
            )
        elif apply:
            parent.mkdir(mode=0o700)
    exists = os.path.lexists(target)
    if exists:
        owned_directory(target, private=True)
        need(
            {p.name for p in target.iterdir()}
            == {"fpcalc", "installation.private.json"},
            "partial or unexpected version requires reconciliation",
        )
        need(
            read(target / "fpcalc", 0o700) == payload
            and read(target / "installation.private.json", 0o600) == encoded,
            "installed version drift requires reconciliation",
        )
    elif apply:
        need(
            shutil.disk_usage(parent).free >= 32 * GIB + len(payload) + MAX_BYTES,
            "protected capacity floor",
        )
        target.mkdir(
            mode=0o700
        )  # Serializes competing installers; partial versions are retained.
        write_new(target / "fpcalc", payload, 0o700)
        write_new(target / "installation.private.json", encoded, 0o600)
        fd = os.open(target, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    return {
        "dry_run": not apply,
        "installed": exists or apply,
        "changed": apply and not exists,
        "binary": str(target / "fpcalc"),
        **receipt,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--pin", type=Path, default=PIN)
    parser.add_argument("--home", type=Path, default=Path.home())
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--apply", action="store_true")
    action.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        os.umask(0o077)
        print(
            json.dumps(
                install(
                    args.archive,
                    json.loads(args.pin.read_text()),
                    args.home,
                    args.apply,
                ),
                sort_keys=True,
            )
        )
        return 0
    except (OSError, ValueError, KeyError, TypeError, tarfile.TarError):
        print(
            json.dumps(
                {
                    "installed": False,
                    "status": "held_for_reconciliation",
                    "automatic_replay": False,
                }
            )
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
