#!/usr/bin/env python3
"""Prepare a pinned normal-user slskd installation; starting it is explicit.

Run with the already prepared Python runtime. This script never downloads or
installs dependencies, changes Tailscale, or touches existing music writers.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import platform
import plistlib
import pwd
import secrets
import shlex
import shutil
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

LABEL = "com.wyattowalsh.slskd"
RIG_DIR = Path(__file__).resolve().parents[2]
PIN = RIG_DIR / "brew" / "slskd-pin.json"
INTAKE_SOURCE = Path(__file__).resolve().with_name("intake.py")
GIB = 1024**3


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def private_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    st = path.lstat()
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
        raise ValueError("directory must be an owned, real directory")
    path.chmod(0o700)


def private_json(path: Path) -> dict:
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "r", encoding="utf-8") as source:
        st = os.fstat(source.fileno())
        if (
            not stat.S_ISREG(st.st_mode)
            or st.st_uid != os.getuid()
            or st.st_mode & 0o077
        ):
            raise ValueError("private input must be an owned regular 0600 file")
        return json.load(source)


def write_owned(path: Path, payload: bytes, mode: int = 0o600) -> None:
    if path.exists() or path.is_symlink():
        st = path.lstat()
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid():
            raise ValueError("refusing to replace an unowned or nonregular file")
        if path.read_bytes() == payload and stat.S_IMODE(st.st_mode) == mode:
            return
    fd, name = tempfile.mkstemp(prefix=".slskd-", dir=path.parent)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "wb") as target:
            target.write(payload)
            target.flush()
            os.fsync(target.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def checked_archive(archive: Path, pin: dict) -> list[zipfile.ZipInfo]:
    if archive.is_symlink() or not archive.is_file():
        raise ValueError("archive must be a regular local file")
    if digest(archive) != pin["darwin_arm64"]["sha256"]:
        raise ValueError("archive SHA-256 does not match the release pin")
    with zipfile.ZipFile(archive) as source:
        members = source.infolist()
        names = set()
        for member in members:
            name = PurePosixPath(member.filename)
            mode = member.external_attr >> 16
            if (
                name.is_absolute()
                or ".." in name.parts
                or "\\" in member.filename
                or stat.S_ISLNK(mode)
                or name.as_posix() in names
            ):
                raise ValueError("unsafe or duplicate archive member")
            names.add(name.as_posix())
        if "slskd" not in names or "wwwroot/index.html" not in names:
            raise ValueError("archive lacks the native binary or web UI")
        return members


def new_credentials() -> dict:
    return {
        "schema": 1,
        "network_username": "w4w-phone-" + secrets.token_hex(6),
        "network_password": secrets.token_urlsafe(32),
        "web_username": "ww",
        "web_password": secrets.token_urlsafe(24),
        "jwt_key": secrets.token_urlsafe(48),
        "intake_api_key": secrets.token_urlsafe(32),
    }


def validate_credentials(credentials: dict) -> None:
    required = (
        "network_username",
        "network_password",
        "web_username",
        "web_password",
        "jwt_key",
        "intake_api_key",
    )
    if credentials.get("schema") != 1 or any(
        not isinstance(credentials.get(key), str) or not credentials[key].strip()
        for key in required
    ):
        raise ValueError("invalid private credential schema")
    if len(credentials["jwt_key"]) < 32 or len(credentials["intake_api_key"]) < 32:
        raise ValueError("signing and API keys must contain at least 32 characters")
    if credentials["web_password"] == "slskd":
        raise ValueError("default web password is forbidden")


def render_config(state: Path, version: Path, credentials: dict) -> bytes:
    """JSON is a YAML 1.2 subset, avoiding interpolation/quoting ambiguities."""
    validate_credentials(credentials)
    config = {
        "instance_name": "mba-phone-soulseek",
        "remote_configuration": False,
        "remote_file_management": False,
        "flags": {"no_version_check": True},
        "directories": {
            "incomplete": str(state / "incomplete"),
            "downloads": str(state / "completed"),
        },
        "shares": {"directories": [], "cache": {"storage_mode": "disk", "workers": 1}},
        "transfers": {
            "download": {"slots": 2, "destination": {"exists": "rename"}},
            "upload": {"slots": 2},
        },
        "web": {
            "port": 5030,
            "ip_address": "127.0.0.1",
            "https": {"disabled": True},
            "url_base": "/",
            # Upstream validates this field as relative. The LaunchAgent's
            # WorkingDirectory pins its resolution to the admitted version.
            "content_path": "wwwroot",
            "authentication": {
                "disabled": False,
                "username": credentials["web_username"],
                "password": credentials["web_password"],
                "jwt": {"key": credentials["jwt_key"], "ttl": 604800000},
                "api_keys": {
                    "intake": {
                        "key": credentials["intake_api_key"],
                        "role": "readonly",
                        "cidr": "127.0.0.1/32",
                    }
                },
            },
        },
        "soulseek": {
            "username": credentials["network_username"],
            "password": credentials["network_password"],
            "listen_port": 50300,
            "description": "Personal music library; browser controlled from phone.",
        },
    }
    return (json.dumps(config, indent=2, ensure_ascii=False) + "\n").encode()


def render_launch(state: Path, version: Path, home: Path) -> tuple[bytes, bytes]:
    command = [
        str(version / "slskd"),
        "--app-dir",
        str(state / "app"),
        "--config",
        str(state / "slskd.yml"),
    ]
    launcher = (
        "#!/bin/bash\nset -euo pipefail\numask 077\nexec " + shlex.join(command) + "\n"
    ).encode()
    launch = {
        "Label": LABEL,
        "ProgramArguments": [str(state / "run")],
        "WorkingDirectory": str(version),
        "EnvironmentVariables": {"HOME": str(home), "PATH": "/usr/bin:/bin"},
        "RunAtLoad": True,
        "KeepAlive": {"SuccessfulExit": False},
        "ThrottleInterval": 15,
        "ProcessType": "Background",
        "StandardOutPath": str(state / "logs" / "stdout.log"),
        "StandardErrorPath": str(state / "logs" / "stderr.log"),
    }
    return launcher, plistlib.dumps(launch, sort_keys=True)


def install_version(
    archive: Path, version: Path, members: list[zipfile.ZipInfo]
) -> dict:
    expected = {}
    with zipfile.ZipFile(archive) as source:
        for member in members:
            if not member.is_dir():
                expected[member.filename] = hashlib.sha256(
                    source.read(member)
                ).hexdigest()
        if version.exists():
            if version.is_symlink() or any(
                (version / name).is_symlink()
                or not (version / name).is_file()
                or digest(version / name) != sha
                for name, sha in expected.items()
            ):
                raise ValueError(
                    "existing pinned version differs; reconcile it instead of overwriting"
                )
            return expected
        stage = Path(tempfile.mkdtemp(prefix=".stage-", dir=version.parent))
        try:
            for member in members:
                target = stage / member.filename
                if member.is_dir():
                    target.mkdir(parents=True, exist_ok=True, mode=0o700)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
                    target.write_bytes(source.read(member))
                    target.chmod(0o700 if member.filename == "slskd" else 0o600)
            os.rename(stage, version)
        finally:
            if stage.exists():
                shutil.rmtree(stage)
    return expected


def loaded() -> bool:
    return (
        subprocess.run(
            ["/bin/launchctl", "print", f"gui/{os.getuid()}/{LABEL}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode
        == 0
    )


def install(archive: Path, pin: dict, home: Path, create: bool, start: bool) -> dict:
    if (
        platform.system() != "Darwin"
        or platform.machine() != "arm64"
        or os.getuid() == 0
    ):
        raise ValueError("apply requires the normal Apple Silicon macOS account")
    if home.resolve() != Path(pwd.getpwuid(os.getuid()).pw_dir).resolve():
        raise ValueError("target home does not belong to the current login account")
    state = home / ".local" / "share" / "slskd"
    if state.is_symlink() or not state.resolve().is_relative_to(home.resolve()):
        raise ValueError("state must remain inside the target home")
    private_dir(state)
    lock_fd = os.open(
        state / ".install.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600
    )
    with os.fdopen(lock_fd, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        members = checked_archive(archive, pin)
        required = sum(x.file_size for x in members) + GIB
        if shutil.disk_usage(state).free < 32 * GIB + required:
            raise ValueError(
                "insufficient space above the protected 32 GiB floor and install reserve"
            )
        credentials_path = state / "credentials.private.json"
        is_loaded = loaded()
        if not credentials_path.exists():
            if not create or is_loaded:
                raise ValueError(
                    "private credentials absent; explicit --create-credentials is required"
                )
            write_owned(
                credentials_path,
                (json.dumps(new_credentials(), indent=2) + "\n").encode(),
            )
        credentials = private_json(credentials_path)
        validate_credentials(credentials)
        version = state / "versions" / pin["version"]
        config = render_config(state, version, credentials)
        launcher, plist = render_launch(state, version, home)
        outputs = {
            state / "slskd.yml": config,
            state / "run": launcher,
            state / "launchagent.plist": plist,
            state / "intake.py": INTAKE_SOURCE.read_bytes(),
        }
        if is_loaded and any(
            not p.is_file() or p.is_symlink() or p.read_bytes() != b
            for p, b in outputs.items()
        ):
            raise ValueError(
                "running service differs; stop and reconcile before changing its closure"
            )
        for name in (
            "versions",
            "app",
            "incomplete",
            "completed",
            "candidates",
            "logs",
        ):
            private_dir(state / name)
        files = install_version(archive, version, members)
        for path, payload in outputs.items():
            write_owned(path, payload, 0o700 if path.name == "run" else 0o600)
        receipt = {
            "schema": 1,
            "version": pin["version"],
            "archive_sha256": pin["darwin_arm64"]["sha256"],
            "files": files,
            "managed_files": {
                str(p.relative_to(state)): hashlib.sha256(b).hexdigest()
                for p, b in outputs.items()
            },
        }
        write_owned(
            state / "installation.private.json",
            (json.dumps(receipt, indent=2) + "\n").encode(),
        )
        if start:
            agents = home / "Library" / "LaunchAgents"
            agents.mkdir(parents=True, exist_ok=True)
            target = agents / (LABEL + ".plist")
            if is_loaded and (
                not target.is_file()
                or target.is_symlink()
                or target.read_bytes() != plist
            ):
                raise ValueError("loaded LaunchAgent differs from the admitted service")
            write_owned(target, plist)
            if not is_loaded:
                subprocess.run(
                    ["/bin/launchctl", "bootstrap", f"gui/{os.getuid()}", str(target)],
                    check=True,
                    capture_output=True,
                )
                if not loaded():
                    raise ValueError("bootstrap returned without the named service")
        return {
            "installed": True,
            "version": pin["version"],
            "state_dir": str(state),
            "credentials_file": str(credentials_path),
            "start_requested": start,
            "loaded": loaded(),
            "network_login_verified": False,
            "phone_access_verified": False,
            "canonical_writes": False,
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--pin", type=Path, default=PIN)
    parser.add_argument("--home", type=Path, default=Path.home())
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--apply", action="store_true")
    action.add_argument("--dry-run", action="store_true")
    parser.add_argument("--create-credentials", action="store_true")
    parser.add_argument("--start", action="store_true")
    args = parser.parse_args()
    try:
        pin = json.loads(args.pin.read_text())
        members = checked_archive(args.archive, pin)
        if args.start and not args.apply:
            raise ValueError("--start requires --apply")
        if args.apply:
            result = install(
                args.archive, pin, args.home, args.create_credentials, args.start
            )
        else:
            result = {
                "dry_run": True,
                "version": pin["version"],
                "archive_verified": True,
                "expanded_bytes": sum(x.file_size for x in members),
                "state_dir": str(args.home / ".local/share/slskd"),
                "intake_sha256": digest(INTAKE_SOURCE),
                "activation": "explicit --apply --start",
                "writes_performed": False,
            }
        print(json.dumps(result, sort_keys=True))
        return 0
    except (ValueError, OSError, zipfile.BadZipFile, subprocess.SubprocessError) as exc:
        # Exception class is enough for unexpected process/OS errors; never print
        # child output or a private configuration/credential payload.
        message = str(exc) if isinstance(exc, ValueError) else type(exc).__name__
        print(
            json.dumps({"ok": False, "error": message}), file=__import__("sys").stderr
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
