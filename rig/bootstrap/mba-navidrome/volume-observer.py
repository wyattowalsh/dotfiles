"""macOS metadata adapter for the existing reader guard; no discovery CLI.

Only the operator-pinned mount is inspected. diskutil's plist metadata is
cross-checked against stat(2) device identities for each requested guard path.
Importing this module performs no host, volume or subprocess observations.
"""

from __future__ import annotations

import os
import plistlib
import re
import socket
import stat
import subprocess
import sys
import uuid
from pathlib import Path

from mba_navidrome_guard import GuardError, VolumeIdentity, _no_symlink_path

DISKUTIL = "/usr/sbin/diskutil"
DEVICE = re.compile(r"disk[0-9]+(?:s[0-9]+)*\Z")


def observe_host() -> str:
    """Return the OS hostname, without DNS, SSH or a configured fallback."""
    return socket.gethostname()


def _diskutil_plist(arguments: list[str]) -> dict:
    try:
        result = subprocess.run(
            [DISKUTIL, *arguments],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
            timeout=10,
            env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"},
        )
        if len(result.stdout) > 1024 * 1024:
            raise GuardError("oversize diskutil metadata")
        payload = plistlib.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, ValueError, plistlib.InvalidFileException) as exc:
        raise GuardError("diskutil metadata is unavailable or malformed") from exc
    if not isinstance(payload, dict):
        raise GuardError("diskutil metadata is not a dictionary")
    return payload


def _device_stat(path: Path) -> os.stat_result:
    """Kept separate so fixture tests never need a real device node."""
    return path.stat()


class MacOSVolumeObserver:
    """Inspect the exact configured mount, never infer identity from a witness."""

    def __init__(self, mountpoint: Path) -> None:
        if not mountpoint.is_absolute() or mountpoint == Path("/") or ".." in mountpoint.parts:
            raise GuardError("an explicit normalized mountpoint is required")
        self.mountpoint = mountpoint

    def __call__(self, path: Path) -> VolumeIdentity:
        if sys.platform != "darwin":
            raise GuardError("production volume observation requires macOS")
        if not path.is_absolute() or ".." in path.parts or not path.is_relative_to(self.mountpoint):
            raise GuardError("observed path is outside the pinned mount")
        before = _no_symlink_path(path, "path")
        mounted = _no_symlink_path(self.mountpoint, "directory")
        if before.st_dev != mounted.st_dev:
            raise GuardError("guard path crossed the pinned volume")

        info = _diskutil_plist(["info", "-plist", os.fspath(self.mountpoint)])
        device = info.get("DeviceIdentifier")
        container = info.get("APFSContainerReference")
        if (
            ("Mounted" in info and info["Mounted"] is not True)
            or info.get("MountPoint") != os.fspath(self.mountpoint)
            or info.get("FilesystemType") != "apfs"
            or type(info.get("Internal")) is not bool
            or not isinstance(device, str) or DEVICE.fullmatch(device) is None
            or not isinstance(container, str) or DEVICE.fullmatch(container) is None
            or info.get("DeviceNode") != f"/dev/{device}"
        ):
            raise GuardError("diskutil did not identify the exact mounted APFS volume")
        try:
            volume_uuid = str(uuid.UUID(info["VolumeUUID"]))
        except (KeyError, TypeError, ValueError, AttributeError) as exc:
            raise GuardError("diskutil volume UUID is missing or invalid") from exc
        node = _device_stat(Path(info["DeviceNode"]))
        if not stat.S_ISBLK(node.st_mode) or node.st_rdev != mounted.st_dev:
            raise GuardError("device node and observed filesystem disagree")

        # `apfs list` accepts an explicit container reference. Do not enumerate
        # every disk or guess a Data role from its name, path or configuration.
        apfs = _diskutil_plist(["apfs", "list", "-plist", container])
        containers = apfs.get("Containers")
        if not isinstance(containers, list) or len(containers) != 1:
            raise GuardError("APFS container observation is ambiguous")
        selected = containers[0]
        if not isinstance(selected, dict) or selected.get("ContainerReference") != container:
            raise GuardError("APFS container reference does not match")
        volumes = selected.get("Volumes")
        if not isinstance(volumes, list) or any(not isinstance(item, dict) for item in volumes):
            raise GuardError("APFS volume metadata is malformed")
        matching = [item for item in volumes if item.get("DeviceIdentifier") == device]
        if len(matching) != 1:
            raise GuardError("APFS volume observation is ambiguous")
        volume = matching[0]
        roles = volume.get("Roles")
        try:
            same_uuid = str(uuid.UUID(volume["APFSVolumeUUID"])) == volume_uuid
        except (KeyError, TypeError, ValueError, AttributeError) as exc:
            raise GuardError("APFS role metadata has no valid volume UUID") from exc
        if (
            not same_uuid
            # Current native diskutil omits Mounted in info and may omit/null
            # MountPoint in apfs-list. Exact info mount + stat/device/UUID above
            # still prove identity; explicit contradictory/unmounted data fails.
            or volume.get("MountPoint") not in (None, os.fspath(self.mountpoint))
            or ("Mounted" in volume and volume["Mounted"] is not True)
            or not isinstance(roles, list)
            or any(not isinstance(role, str) or not role for role in roles)
            or len(roles) > 1
        ):
            raise GuardError("APFS role, UUID or mountpoint is inconsistent")
        after = _no_symlink_path(path, "path")
        remounted = _no_symlink_path(self.mountpoint, "directory")
        if (before.st_dev, before.st_ino) != (after.st_dev, after.st_ino) or (
            mounted.st_dev, mounted.st_ino
        ) != (remounted.st_dev, remounted.st_ino):
            raise GuardError("guard path or mount changed during observation")
        return VolumeIdentity(
            volume_uuid, self.mountpoint, "apfs", roles[0] if roles else "", info["Internal"]
        )
