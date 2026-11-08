"""Offline NV01/NV02 guard contract; intentionally has no production entry point.

The mount observer and child launcher are injected for synthetic tests. Do not
connect a real Navidrome until its versioned non-purging setting, MBA host and
APFS topology, E0 witness, and a trustworthy OS mount observer are verified.
"""

from __future__ import annotations

import hashlib
import json
import os
import stat
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Protocol


class GuardError(RuntimeError):
    """A guard precondition failed; no reader may be started or restarted."""


@dataclass(frozen=True)
class VolumeIdentity:
    """Observed by a trusted mount inspector, NOT copied from the config."""

    apfs_uuid: str
    mountpoint: Path
    filesystem: str
    apfs_role: str = ""
    internal: bool | None = None


@dataclass(frozen=True)
class ReaderContract:
    hostname: str
    apfs_uuid: str
    mountpoint: Path
    media_root: Path
    witness: Path
    epoch: str
    state_dir: Path
    topology: str = "external-dedicated"

    def validate(self) -> None:
        if not self.hostname.strip() or not self.epoch.strip():
            raise GuardError("hostname and published epoch must be configured")
        try:
            uuid.UUID(self.apfs_uuid)
        except ValueError as exc:
            raise GuardError("configured APFS volume UUID is invalid") from exc
        paths = (self.mountpoint, self.media_root, self.witness, self.state_dir)
        if any(not path.is_absolute() or ".." in path.parts for path in paths):
            raise GuardError("all paths must be absolute and normalized")
        if self.topology not in ("external-dedicated", "internal-data"):
            raise GuardError("unrecognized media volume topology")
        if self.mountpoint == Path("/") or self.media_root == self.mountpoint:
            raise GuardError("an explicit APFS mount and media subdirectory are required")
        if not self.media_root.is_relative_to(self.mountpoint):
            raise GuardError("media root is outside the configured mountpoint")
        if not self.witness.is_relative_to(self.mountpoint):
            raise GuardError("published witness is outside the configured mountpoint")
        if self.witness.is_relative_to(self.media_root):
            raise GuardError("witness must not be scanned as media")
        if self.state_dir.is_relative_to(self.media_root) or self.state_dir == self.mountpoint:
            raise GuardError("loss latch must persist outside the media tree")
        if self.topology == "external-dedicated" and self.state_dir.is_relative_to(
            self.mountpoint
        ):
            raise GuardError("external media loss latch must persist off the volume")
        if self.topology == "internal-data" and not self.state_dir.is_relative_to(
            self.mountpoint
        ):
            raise GuardError("internal Data loss latch must reside on the Data volume")


class Child(Protocol):
    def poll(self) -> int | None: ...

    def terminate(self) -> None: ...

    def wait(self, timeout: float) -> int: ...

    def kill(self) -> None: ...


HostObserver = Callable[[], str]
MountObserver = Callable[[Path], VolumeIdentity | None]


def _no_symlink_path(path: Path, kind: str) -> os.stat_result:
    """Reject symlinks in the entire prefix, not just the final component."""
    current = Path("/")
    try:
        for part in path.parts[1:]:
            current /= part
            mode = current.lstat().st_mode
            if stat.S_ISLNK(mode):
                raise GuardError(f"symlink is not approved: {current}")
        result = path.lstat()
    except (OSError, ValueError) as exc:
        raise GuardError(f"missing or unreadable {kind}: {path}") from exc
    if kind == "directory" and not stat.S_ISDIR(result.st_mode):
        raise GuardError(f"not a directory: {path}")
    if kind == "file" and not stat.S_ISREG(result.st_mode):
        raise GuardError(f"not a regular file: {path}")
    return result


def _relative_file(root: Path, relative: str) -> Path:
    if not relative or "\\" in relative:
        raise GuardError("witness sample has an invalid relative path")
    posix = PurePosixPath(relative)
    if posix.is_absolute() or any(p in ("", ".", "..") for p in relative.split("/")):
        raise GuardError("witness sample escapes the media root")
    path = root.joinpath(*posix.parts)
    _no_symlink_path(path, "file")
    return path


def _read_regular(path: Path) -> bytes:
    _no_symlink_path(path, "file")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(path, flags)
        with os.fdopen(fd, "rb") as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                raise GuardError(f"not a regular file: {path}")
            return stream.read()
    except OSError as exc:
        raise GuardError(f"cannot read guarded file: {path}") from exc


def _media_census(root: Path) -> tuple[int, int]:
    """Full conservative scan: no links or special files anywhere in tree."""
    _no_symlink_path(root, "directory")
    pending = [root]
    count = size = 0
    while pending:
        directory = pending.pop()
        try:
            with os.scandir(directory) as entries:
                for entry in entries:
                    info = entry.stat(follow_symlinks=False)
                    if stat.S_ISLNK(info.st_mode):
                        raise GuardError(f"unapproved media symlink: {entry.path}")
                    if stat.S_ISDIR(info.st_mode):
                        pending.append(Path(entry.path))
                    elif stat.S_ISREG(info.st_mode):
                        count += 1
                        size += info.st_size
                    else:
                        raise GuardError(f"special file in media tree: {entry.path}")
        except OSError as exc:
            raise GuardError(f"cannot census media directory: {directory}") from exc
    return count, size


class ReaderGuard:
    """One-shot synthetic supervisor; no CLI, install, writer, or auto-rearm."""

    def __init__(
        self,
        contract: ReaderContract,
        observe_host: HostObserver,
        observe_mount: MountObserver,
    ) -> None:
        self.contract = contract
        self.observe_host = observe_host
        self.observe_mount = observe_mount
        self.contract.validate()

    @property
    def latch_path(self) -> Path:
        return self.contract.state_dir / "volume-loss-latched.json"

    def _check_latch(self) -> None:
        _no_symlink_path(self.contract.state_dir, "directory")
        try:
            self.latch_path.lstat()
        except FileNotFoundError:
            return
        except OSError as exc:
            raise GuardError("cannot inspect persistent loss latch") from exc
        raise GuardError("volume loss latched; manual reconciliation required")

    def verify(self) -> None:
        self._verify(skip_latch=False)

    def _verify(self, *, skip_latch: bool) -> None:
        self.contract.validate()
        if not skip_latch:
            self._check_latch()
        paths = (
            self.contract.mountpoint,
            self.contract.media_root,
            self.contract.witness,
        )
        if self.contract.topology == "internal-data":
            paths += (self.contract.state_dir,)
        try:
            host = self.observe_host()
            observations = [self.observe_mount(path) for path in paths]
            matches = all(
                observed is not None
                and observed.filesystem.lower() == "apfs"
                and observed.mountpoint == self.contract.mountpoint
                and observed.apfs_uuid.lower() == self.contract.apfs_uuid.lower()
                and (
                    self.contract.topology != "internal-data"
                    or (
                        observed.apfs_role.lower() == "data"
                        and observed.internal is True
                    )
                )
                and (
                    self.contract.topology != "external-dedicated"
                    or (observed.internal is not True and observed.apfs_role.lower() != "data")
                )
                for observed in observations
            )
        except Exception as exc:
            raise GuardError("host or mount observer failed") from exc
        if host != self.contract.hostname:
            raise GuardError("host identity does not match")
        if not matches:
            raise GuardError("actual APFS UUID, role, location or mountpoint does not match")
        _no_symlink_path(self.contract.mountpoint, "directory")
        _no_symlink_path(self.contract.media_root, "directory")
        _no_symlink_path(self.contract.state_dir, "directory")
        try:
            witness = json.loads(_read_regular(self.contract.witness))
            sample = witness["sample"]
            count = witness["file_count"]
            size = witness["total_bytes"]
            if witness["epoch"] != self.contract.epoch:
                raise GuardError("published witness epoch does not match")
            if type(count) is not int or type(size) is not int or count < 1 or size < 1:
                raise GuardError("published media witness is empty or invalid")
            sample_path = _relative_file(self.contract.media_root, sample["path"])
            if sample_path.stat().st_size < 1:
                raise GuardError("media sample is empty")
            digest = hashlib.sha256(_read_regular(sample_path)).hexdigest()
            if digest != sample["sha256"]:
                raise GuardError("published media sample hash does not match")
        except (KeyError, TypeError, ValueError, UnicodeError) as exc:
            raise GuardError("published media witness is malformed") from exc
        if _media_census(self.contract.media_root) != (count, size):
            raise GuardError("published media census no longer matches the witness")

    def _latch_loss(self, reason: str) -> None:
        """Durably record loss outside the volume. Never delete or auto-rearm."""
        _no_symlink_path(self.contract.state_dir, "directory")
        if self.latch_path.exists() or self.latch_path.is_symlink():
            return
        temp = self.contract.state_dir / f".volume-loss-{uuid.uuid4().hex}.tmp"
        payload = json.dumps({"reason": reason, "epoch": self.contract.epoch}) + "\n"
        try:
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
            fd = os.open(temp, flags, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temp, self.latch_path)
            directory_fd = os.open(self.contract.state_dir, os.O_RDONLY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        except OSError as exc:
            raise GuardError(
                "could not durably latch loss; startup must stay blocked"
            ) from exc
        finally:
            temp.unlink(missing_ok=True)

    @staticmethod
    def _stop(child: Child) -> None:
        try:
            if child.poll() is not None:
                return
            child.terminate()
            try:
                child.wait(timeout=5)
            except TimeoutError:
                child.kill()
                child.wait(timeout=5)
            if child.poll() is None:
                raise GuardError("reader shutdown was not confirmed")
        except (OSError, TimeoutError) as exc:
            raise GuardError("reader shutdown was not confirmed") from exc

    def transition_to_e1(
        self,
        child: Child,
        disable_reader: Callable[[], bool],
        demote: Callable[[], None],
    ) -> None:
        """Synthetic E1: latch, stop, positively disable, then demote.

        A completed transition stays latched until manual reconciliation. Neither
        callback is an OS or Navidrome adapter; callers must inject fakes here.
        """
        self._latch_loss("e1-incomplete: manual reconciliation required")
        self._stop(child)
        try:
            disabled = disable_reader()
        except Exception as exc:
            raise GuardError("reader disable failed; E1 demotion prohibited") from exc
        if disabled is not True:
            raise GuardError("reader not positively disabled; E1 demotion prohibited")
        self._verify(skip_latch=True)
        try:
            demote()
        except Exception as exc:
            raise GuardError("E1 demotion incomplete; manual reconciliation required") from exc

    def rearm_manually(self, manual_verification: Callable[[], bool]) -> None:
        """Synthetic explicit rearm after new witnessed epoch and human verification.

        There is deliberately no automatic call to this method or real adapter.
        """
        try:
            latch = json.loads(_read_regular(self.latch_path))
            if (
                not isinstance(latch, dict)
                or not isinstance(latch.get("reason"), str)
                or not latch["reason"]
                or not isinstance(latch.get("epoch"), str)
                or not latch["epoch"]
            ):
                raise GuardError("persistent latch is malformed")
            if latch["reason"].startswith("e1-incomplete:") and (
                latch.get("epoch") == self.contract.epoch
            ):
                raise GuardError("E1 requires a newly published epoch before rearm")
        except (ValueError, UnicodeError, TypeError) as exc:
            raise GuardError("persistent latch is malformed") from exc
        self._verify(skip_latch=True)
        try:
            confirmed = manual_verification()
        except Exception as exc:
            raise GuardError("manual rearm verification failed") from exc
        if confirmed is not True:
            raise GuardError("manual rearm was not positively verified")
        self._verify(skip_latch=True)
        _no_symlink_path(self.latch_path, "file")
        try:
            self.latch_path.unlink()
            fd = os.open(self.contract.state_dir, os.O_RDONLY)
            try:
                os.fsync(fd)
            finally:
                os.close(fd)
        except OSError as exc:
            raise GuardError("manual rearm could not be persisted") from exc

    def run_once(
        self, start_child: Callable[[], Child], tick: Callable[[], None]
    ) -> int:
        """Start one injected child only after preflight; stop and latch on loss.

        The injected child is a synthetic Navidrome stand-in in this prototype.
        No production startup adapter is supplied, by design.
        """
        self.verify()
        try:
            child = start_child()
        except Exception as exc:
            self._latch_loss("reader start failed")
            raise GuardError("reader start failed; manual rearm required") from exc
        try:
            while (status := child.poll()) is None:
                self.verify()
                tick()
            if status != 0:
                self._latch_loss(f"reader crashed with exit status {status}")
            return status
        except Exception as exc:
            self._latch_loss(str(exc))
            if isinstance(exc, GuardError):
                raise
            raise GuardError("running guard tick failed") from exc
        finally:
            self._stop(child)
