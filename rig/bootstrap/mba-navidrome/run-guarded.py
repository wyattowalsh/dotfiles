"""One-shot MBA reader adapter; no installer, publication, mkdir or auto-retry.

The trusted operator contract and a published E1 witness are prerequisites, not
outputs of this launcher. The existing ReaderGuard owns verification/latching.
The child can write derived state only, never the canonical music library.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
import signal
import sqlite3
import stat
import subprocess
import sys
import time
import tomllib
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

# Explicit source-file imports avoid adding a writable working directory to the
# module search path. Both adapters use this one existing guard module instance.
SOURCE_DIR = Path(__file__).absolute().parent
if "mba_navidrome_guard" not in sys.modules:
    spec = importlib.util.spec_from_file_location("mba_navidrome_guard", SOURCE_DIR / "guard.py")
    assert spec is not None and spec.loader is not None
    guard_module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = guard_module
    spec.loader.exec_module(guard_module)
spec = importlib.util.spec_from_file_location(
    "mba_navidrome_volume_observer", SOURCE_DIR / "volume-observer.py"
)
assert spec is not None and spec.loader is not None
observer = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = observer
spec.loader.exec_module(observer)

from mba_navidrome_guard import GuardError, ReaderContract, ReaderGuard, _no_symlink_path, _read_regular

SANDBOX = "/usr/bin/sandbox-exec"
SANDBOX_PROFILE = '(version 1)\n(allow default)\n(deny file-write* (require-not (subpath (param "DATA"))))\n'
MAX_CONFIG_BYTES = 65_536
UNCLEAN_RUN = "reader-unclean.json"
RESTORE_ADMISSION = "reader-restore-admission.json"
NATIVE_TABLES = ("user", "playlist", "playlist_tracks", "annotation", "media_file",
                 "folder", "library", "album", "artist", "bookmark", "playqueue", "property")
IDENTITY_TABLES = ("user", "playlist", "playlist_tracks", "annotation", "media_file", "folder", "library")

# A task-specific session anchor, not a shell or a second service. It reports
# Navidrome's status without letting the supervisor reap/reuse the group leader.
# The actual sandboxed reader and its ordinary helpers inherit this session and
# group. TERM leaves the anchor in place for bounded group-wide KILL escalation.
# Supervisor death closes the control pipe: the anchor then kills its OWN group,
# but deliberately cannot clear the supervisor's durable unclean-run interlock.
SESSION_ANCHOR = """
import os
import select
import signal
import subprocess
import sys

status_fd, control_fd = map(int, sys.argv[1:3])
if os.getpgrp() != os.getpid() or os.getsid(0) != os.getpid():
    raise SystemExit(2)
signal.signal(signal.SIGTERM, lambda *_: None)
signal.signal(signal.SIGINT, lambda *_: None)
signal.signal(signal.SIGHUP, lambda *_: None)
try:
    reader = subprocess.Popen(sys.argv[3:], stdin=subprocess.DEVNULL, close_fds=True)
except Exception:
    reader = None
reported = False
while True:
    status = reader.poll() if reader is not None else "failed"
    if status is not None and not reported:
        try:
            os.write(status_fd, (str(status) + "\\n").encode("ascii"))
        except BrokenPipeError:
            pass
        os.close(status_fd)
        reported = True
    if select.select([control_fd], [], [], 0.1)[0]:
        if not os.read(control_fd, 1):
            os.killpg(os.getpgrp(), signal.SIGKILL)
"""


def _pairs(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise GuardError("duplicate operator configuration field")
        result[key] = value
    return result


def _path(value: object) -> Path:
    if not isinstance(value, str) or any(ord(char) < 32 for char in value):
        raise GuardError("configured paths must be literal absolute strings")
    path = Path(value)
    if not path.is_absolute() or str(path) != value or ".." in path.parts:
        raise GuardError("configured paths must be literal normalized absolute paths")
    return path


def _private_directory(path: Path) -> None:
    entry = _no_symlink_path(path, "directory")
    if entry.st_uid != os.getuid() or stat.S_IMODE(entry.st_mode) & 0o077:
        raise GuardError("runtime directories must already exist, be caller-owned and private")


def _trusted_read(path: Path) -> bytes:
    entry = _no_symlink_path(path, "file")
    parent = _no_symlink_path(path.parent, "directory")
    if (
        entry.st_uid != os.getuid() or stat.S_IMODE(entry.st_mode) & 0o077 or entry.st_nlink != 1
        or parent.st_uid not in (0, os.getuid()) or stat.S_IMODE(parent.st_mode) & 0o022
    ):
        raise GuardError("operator configuration must be private and protected from other writers")
    if entry.st_size > MAX_CONFIG_BYTES:
        raise GuardError("oversize operator configuration")
    flags = os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_NONBLOCK", 0)
    fd = os.open(path, flags)
    with os.fdopen(fd, "rb") as stream:
        opened = os.fstat(stream.fileno())
        if (opened.st_dev, opened.st_ino, opened.st_mode, opened.st_size) != (
            entry.st_dev, entry.st_ino, entry.st_mode, entry.st_size
        ) or opened.st_uid != os.getuid() or opened.st_nlink != 1:
            raise GuardError("operator configuration changed while opening")
        payload = stream.read(MAX_CONFIG_BYTES + 1)
    if len(payload) > MAX_CONFIG_BYTES:
        raise GuardError("oversize operator configuration")
    return payload


@dataclass(frozen=True)
class RuntimeConfig:
    contract: ReaderContract
    binary: Path
    binary_sha256: str
    navidrome_config: Path
    data_dir: Path
    address: str
    port: int
    poll_seconds: int
    native_version: str
    restore_witness: Path
    restore_witness_sha256: str


def load_config(path: Path) -> RuntimeConfig:
    import ipaddress

    data = json.loads(_trusted_read(path), object_pairs_hook=_pairs)
    required = {
        "schema_version", "publication_state", "hostname", "apfs_uuid", "mountpoint",
        "media_root", "witness", "epoch", "state_dir", "topology", "binary",
        "binary_sha256", "navidrome_config", "data_dir", "address", "port", "poll_seconds",
        "native_version", "restore_witness", "restore_witness_sha256",
    }
    if not isinstance(data, dict) or set(data) != required or type(data["schema_version"]) is not int or data["schema_version"] != 1:
        raise GuardError("unsupported operator contract schema")
    if data["publication_state"] != "E1":
        raise GuardError("production startup requires an explicitly published E1, not an E0 pilot")
    for key in ("hostname", "apfs_uuid", "epoch", "topology"):
        if not isinstance(data[key], str) or not data[key] or data[key].strip() != data[key]:
            raise GuardError("invalid operator identity or published epoch")
    contract = ReaderContract(
        hostname=data["hostname"], apfs_uuid=data["apfs_uuid"],
        mountpoint=_path(data["mountpoint"]), media_root=_path(data["media_root"]),
        witness=_path(data["witness"]), epoch=data["epoch"], state_dir=_path(data["state_dir"]),
        topology=data["topology"],
    )
    contract.validate()
    binary = _path(data["binary"])
    nav_config = _path(data["navidrome_config"])
    derived = _path(data["data_dir"])
    restore_witness = _path(data["restore_witness"])
    protected = (path, nav_config, binary, restore_witness, contract.media_root, contract.witness, contract.state_dir)
    if derived == Path("/") or any(item.is_relative_to(derived) for item in protected):
        raise GuardError("derived-state writes must not cover configuration, media, witness or guard state")
    if derived.is_relative_to(contract.media_root) or derived.is_relative_to(contract.state_dir):
        raise GuardError("derived and canonical/guard state must be separate")
    if any(item.is_relative_to(contract.media_root) for item in (path, nav_config, binary, restore_witness)):
        raise GuardError("configuration and executable must be outside the scanned tree")
    if contract.topology == "internal-data" and not derived.is_relative_to(contract.mountpoint):
        raise GuardError("internal reader derived state must remain on the pinned Data volume")
    if contract.topology == "external-dedicated" and derived.is_relative_to(contract.mountpoint):
        raise GuardError("external media must not contain the reader's writable state")
    digest = data["binary_sha256"]
    if not isinstance(digest, str) or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
        raise GuardError("the reviewed installed Navidrome binary must be SHA-256 pinned")
    restore_digest = data["restore_witness_sha256"]
    if not _is_digest(restore_digest):
        raise GuardError("the independent database restore witness must be SHA-256 pinned")
    native_version = data["native_version"]
    if not isinstance(native_version, str) or not 1 <= len(native_version) <= 256 or any(ord(c) < 32 for c in native_version):
        raise GuardError("an exact observed native Navidrome version is required")
    if not isinstance(data["address"], str):
        raise GuardError("an explicit reviewed IP bind address is required")
    address = ipaddress.ip_address(data["address"])
    mapped = getattr(address, "ipv4_mapped", None)
    if address.is_unspecified or address.is_multicast or (mapped is not None and (mapped.is_unspecified or mapped.is_multicast)) or str(address) != data["address"]:
        raise GuardError("wildcard, multicast or ambiguous reader bind is forbidden")
    if type(data["port"]) is not int or not 1024 <= data["port"] <= 65535:
        raise GuardError("an explicit unprivileged reader port is required")
    if type(data["poll_seconds"]) is not int or not 1 <= data["poll_seconds"] <= 60:
        raise GuardError("guard poll interval must be between 1 and 60 seconds")
    _private_directory(contract.state_dir)
    _private_directory(derived)
    _private_directory(derived / "cache")
    return RuntimeConfig(contract, binary, digest, nav_config, derived, str(address), data["port"], data["poll_seconds"],
                         native_version, restore_witness, restore_digest)


def _is_digest(value: object) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def _canonical(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def restored_database_metadata(path: Path) -> dict:
    """Read a standalone restored DB; never open a live WAL tuple or change IDs."""
    entry = _no_symlink_path(path, "file")
    if entry.st_uid != os.getuid() or entry.st_nlink != 1 or stat.S_IMODE(entry.st_mode) & 0o077 or entry.st_size == 0:
        raise GuardError("restored database must be an existing private owned regular file")
    for suffix in ("-wal", "-shm", "-journal"):
        sidecar = Path(str(path) + suffix)
        if sidecar.exists() or sidecar.is_symlink():
            raise GuardError("first admission requires a consistent standalone database without a WAL/journal")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        opened = os.fstat(fd)
        if (opened.st_dev, opened.st_ino) != (entry.st_dev, entry.st_ino):
            raise GuardError("restored database changed while opening")
        digest = hashlib.sha256()
        while chunk := os.read(fd, 1024 * 1024):
            digest.update(chunk)
        connection = sqlite3.connect(path.as_uri() + "?mode=ro&immutable=1", uri=True, timeout=2)
        try:
            connection.execute("PRAGMA query_only=ON")
            if connection.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
                raise GuardError("restored database integrity check failed")
            schema = connection.execute("SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name").fetchall()
            names = {r[1] for r in schema if r[0] == "table"}
            if not set(NATIVE_TABLES) <= names:
                raise GuardError("restored database lacks native application tables")
            counts = {name: connection.execute('SELECT count(*) FROM "' + name + '"').fetchone()[0]
                      for name in NATIVE_TABLES}
            if not counts["user"] or not counts["media_file"] or connection.execute("SELECT id FROM library ORDER BY id").fetchall() != [(1,)]:
                raise GuardError("restored database requires users, media and the preserved default library ID")
            for name in ("media_file", "folder"):
                for value, in connection.execute('SELECT path FROM "' + name + '"'):
                    if not isinstance(value, str) or Path(value).is_absolute() or ".." in Path(value).parts:
                        raise GuardError("native media and folder paths must remain library-relative")
            identities = {}
            for name in IDENTITY_TABLES:
                columns = [r[1] for r in connection.execute('PRAGMA table_info("' + name + '")')
                           if r[1] == "id" or r[1].endswith("_id") or r[1] == "item_type"]
                if not columns:
                    raise GuardError("native identity columns are missing")
                rows = connection.execute('SELECT ' + ",".join('"' + c.replace('"', '""') + '"' for c in columns) + ' FROM "' + name + '"')
                encoded = sorted(_canonical([(type(v).__name__, v.hex() if isinstance(v, bytes) else v) for v in row])
                                 for row in rows)
                identities[name] = {"columns": columns, "sha256": hashlib.sha256(b"".join(encoded)).hexdigest()}
        finally:
            connection.close()
        after = _no_symlink_path(path, "file")
        fields = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns", "st_uid", "st_mode", "st_nlink")
        if any(getattr(entry, k) != getattr(after, k) or getattr(entry, k) != getattr(os.fstat(fd), k) for k in fields):
            raise GuardError("restored database changed during admission")
        return {"sha256": digest.hexdigest(), "schema_sha256": hashlib.sha256(_canonical(schema)).hexdigest(),
                "selected_table_counts": counts, "id_fingerprints": identities}
    except sqlite3.Error as exc:
        raise GuardError("restored database is not readable native SQLite") from exc
    finally:
        os.close(fd)


def verify_database_restore(config: RuntimeConfig, *, admit: bool = False) -> None:
    """An operator admits actual independent recovery; export/counts alone cannot."""
    _no_symlink_path(config.binary, "file")
    digest = hashlib.sha256()
    with os.fdopen(os.open(config.binary, os.O_RDONLY | os.O_NOFOLLOW), "rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    if digest.hexdigest() != config.binary_sha256:
        raise GuardError("installed reader differs from the reviewed native binary")
    raw = _trusted_read(config.restore_witness)
    if hashlib.sha256(raw).hexdigest() != config.restore_witness_sha256:
        raise GuardError("database restore witness changed")
    witness = json.loads(raw, object_pairs_hook=_pairs)
    required = {"schema_version", "source_reader_quiesced", "independent_backup_verified",
                "independent_restore_verified", "support_export", "backup_receipt", "restore_receipt",
                "native_version", "database"}
    if not isinstance(witness, dict) or set(witness) != required or type(witness["schema_version"]) is not int or witness["schema_version"] != 1:
        raise GuardError("unsupported database restore witness")
    if any(witness[k] is not True for k in ("source_reader_quiesced", "independent_backup_verified", "independent_restore_verified")):
        raise GuardError("final source-reader capture and independent backup/restore must be admitted")
    proofs = {}
    for key in ("support_export", "backup_receipt", "restore_receipt"):
        reference = witness[key]
        if not isinstance(reference, dict) or set(reference) != {"path", "sha256"} or not _is_digest(reference["sha256"]):
            raise GuardError("database recovery evidence reference is invalid")
        path = _path(reference["path"])
        if path.is_relative_to(config.data_dir) or path.is_relative_to(config.contract.media_root):
            raise GuardError("recovery evidence must remain outside writable data and media")
        payload = _trusted_read(path)
        if hashlib.sha256(payload).hexdigest() != reference["sha256"]:
            raise GuardError("database recovery evidence changed")
        proofs[key] = payload
    if witness["backup_receipt"] == witness["restore_receipt"] or witness["native_version"] != config.native_version:
        raise GuardError("distinct backup/restore evidence and matching source/target native version are required")
    exported = json.loads(proofs["support_export"], object_pairs_hook=_pairs)
    if not isinstance(exported, dict) or not isinstance(exported.get("files"), list):
        raise GuardError("selected support export is malformed")
    rows = [r for r in exported["files"] if isinstance(r, dict) and r.get("key") == "navidrome-navidrome-db"]
    expected = witness["database"]
    if (exported.get("schema") != "mba-music-selected-support-export-v1" or exported.get("source_unchanged") is not True
            or exported.get("host_paths_rewritten") is not False or len(rows) != 1 or not isinstance(expected, dict)
            or set(expected) != {"sha256", "schema_sha256", "selected_table_counts", "id_fingerprints"}
            or rows[0].get("sha256") != expected.get("sha256") or not _is_digest(expected.get("sha256"))):
        raise GuardError("restored database is not bound to the unchanged selected support export")
    counts = expected["selected_table_counts"]
    fingerprints = expected["id_fingerprints"]
    if (not isinstance(counts, dict) or set(counts) != set(NATIVE_TABLES)
            or any(type(n) is not int or n < 0 for n in counts.values())
            or not isinstance(fingerprints, dict) or set(fingerprints) != set(IDENTITY_TABLES)):
        raise GuardError("restore witness requires dynamic exact native counts and identity fingerprints")
    admission = config.contract.state_dir / RESTORE_ADMISSION
    database = config.data_dir / "navidrome.db"
    entry = _no_symlink_path(database, "file")
    identity = {"device": entry.st_dev, "inode": entry.st_ino}
    if config.contract.topology == "internal-data":
        volume = observer.MacOSVolumeObserver(config.contract.mountpoint)(database)
        if (volume.apfs_uuid.lower() != config.contract.apfs_uuid.lower()
                or volume.mountpoint != config.contract.mountpoint or volume.filesystem != "apfs"
                or volume.apfs_role.lower() != "data" or volume.internal is not True):
            raise GuardError("native database is not on the pinned internal Data volume")
        # st_dev is a boot-local device number. The observer still proves it
        # against the current device node; only UUID/inode persist across boots.
        identity = {"volume_uuid": volume.apfs_uuid.lower(), "inode": entry.st_ino}
    base = {"schema_version": 2, "state": "restoration-admitted-not-native-start-proof",
            "restore_witness_sha256": config.restore_witness_sha256, "binary_sha256": config.binary_sha256,
            "native_version": config.native_version, "database_identity": identity,
            "initial_database_sha256": expected["sha256"]}
    if admission.exists() or admission.is_symlink():
        if json.loads(_trusted_read(admission), object_pairs_hook=_pairs) != base:
            raise GuardError("database identity or prior restoration admission changed")
        # Native updates are expected. Replacement/truncation/fresh catalog is not.
        if entry.st_uid != os.getuid() or entry.st_nlink != 1 or stat.S_IMODE(entry.st_mode) & 0o077:
            raise GuardError("admitted native database is no longer private")
        sidecars = {}
        for suffix in ("-wal", "-shm", "-journal"):
            path = Path(str(database) + suffix)
            if path.exists() or path.is_symlink():
                observed = _no_symlink_path(path, "file")
                if observed.st_uid != os.getuid() or observed.st_nlink != 1 or stat.S_IMODE(observed.st_mode) & 0o077:
                    raise GuardError("native SQLite sidecars must be private owned single-link regular files")
                if suffix == "-journal" and observed.st_size:
                    raise GuardError("native rollback journal requires explicit quiescent reconciliation")
                sidecars[suffix] = (observed.st_dev, observed.st_ino, observed.st_uid, observed.st_mode, observed.st_nlink)
        if "-wal" in sidecars and "-shm" not in sidecars:
            raise GuardError("admitted WAL cannot be read without creating a missing shared-memory index")
        try:
            uri = database.as_uri() + "?mode=ro" + ("" if "-wal" in sidecars else "&immutable=1")
            connection = sqlite3.connect(uri, uri=True, timeout=2)
            try:
                connection.execute("PRAGMA query_only=ON")
                if any(connection.execute('SELECT count(*) FROM "' + name + '"').fetchone()[0] == 0 for name in ("user", "media_file")):
                    raise GuardError("admitted database became a fresh or empty catalog")
            finally:
                connection.close()
        except sqlite3.Error as exc:
            raise GuardError("admitted native database is unreadable") from exc
        for suffix, original in sidecars.items():
            observed = _no_symlink_path(Path(str(database) + suffix), "file")
            if (observed.st_dev, observed.st_ino, observed.st_uid, observed.st_mode, observed.st_nlink) != original:
                raise GuardError("native SQLite sidecar identity changed during admission")
    else:
        actual = restored_database_metadata(database)
        if actual != expected or rows[0].get("database", {}).get("schema_sha256") != actual["schema_sha256"]:
            raise GuardError("restored database hash, counts or native identities differ")
        source_counts = rows[0].get("database", {}).get("selected_table_counts", {})
        if not isinstance(source_counts, dict) or not source_counts or any(actual["selected_table_counts"].get(k) != v for k, v in source_counts.items()):
            raise GuardError("selected support export counts differ from restored database")
    try:
        result = subprocess.run([str(config.binary), "--version"], stdin=subprocess.DEVNULL, capture_output=True,
                                timeout=15, check=False, cwd=config.data_dir,
                                env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "HOME": "/var/empty"})
    except (OSError, subprocess.SubprocessError) as exc:
        raise GuardError("installed native version readback failed") from exc
    if result.returncode != 0 or len(result.stdout) + len(result.stderr) > 4096 or result.stdout.decode("utf-8").strip() != config.native_version:
        raise GuardError("installed native version differs from the admitted source restore")
    after = _no_symlink_path(database, "file")
    if any(getattr(entry, k) != getattr(after, k) for k in ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")):
        raise GuardError("native database changed before reader admission")
    if admit and not admission.exists():
        fd = os.open(admission, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(_canonical(base))
            stream.flush()
            os.fsync(stream.fileno())
        _sync_directory(config.contract.state_dir)


def validate_navidrome(config: RuntimeConfig) -> bytes:
    """Accept only the narrow, separately rendered MBA reader configuration."""
    payload = _trusted_read(config.navidrome_config)
    parsed = tomllib.loads(payload.decode("utf-8"))
    expected = {
        "Address": config.address, "Port": config.port,
        "MusicFolder": str(config.contract.media_root), "DataFolder": str(config.data_dir),
        "CacheFolder": str(config.data_dir / "cache"), "LogLevel": "info",
        "EnableSharing": False, "EnableExternalServices": False,
        "Scanner": {"Schedule": "0", "WatcherWait": "5s", "PurgeMissing": "never"},
    }
    if parsed != expected or any(type(parsed.get(key)) is not type(value) for key, value in expected.items()):
        raise GuardError("MBA Navidrome config must match the pinned non-purging reader policy exactly")
    return payload


class PublishedE1Guard(ReaderGuard):
    """Add an explicit publication phase/path pin; retain the existing machine."""

    def _verify(self, *, skip_latch: bool) -> None:
        super()._verify(skip_latch=skip_latch)
        published = json.loads(_read_regular(self.contract.witness), object_pairs_hook=_pairs)
        if (
            not isinstance(published, dict) or published.get("publication_state") != "E1"
            or published.get("media_root") != str(self.contract.media_root)
            or published.get("epoch") != self.contract.epoch
        ):
            raise GuardError("witness is not the pinned, published E1 tree and epoch")


def _check_unclean_run(state_dir: Path) -> None:
    try:
        (state_dir / UNCLEAN_RUN).lstat()
    except FileNotFoundError:
        return
    except OSError as exc:
        raise GuardError("cannot inspect durable reader interlock") from exc
    # Existence alone blocks, including malformed records and symlinks. Neither
    # PID absence, a free flock, elapsed time nor epoch rearm is cleanup proof.
    raise GuardError("unclean reader run; full owned-session reconciliation required before any operation")


def _sync_directory(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


class RunInterlock:
    """Persist before spawning; only this run's confirmed cleanup can unlink it."""

    def __init__(self, contract: ReaderContract) -> None:
        self.contract = contract
        self.path = contract.state_dir / UNCLEAN_RUN
        self.fd: int | None = None

    def arm(self) -> None:
        _private_directory(self.contract.state_dir)
        _check_unclean_run(self.contract.state_dir)
        fd = os.open(self.path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        self.fd = fd  # retain the inode until cleanup; never adopt an old record
        payload = json.dumps({"schema_version": 1, "epoch": self.contract.epoch,
                              "state": "quiescence-unconfirmed", "run_id": os.urandom(16).hex()}) + "\n"
        with os.fdopen(os.dup(fd), "w", encoding="utf-8") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        _sync_directory(self.contract.state_dir)

    def clear_after_quiescence(self, child: OwnedChild) -> None:
        if not child.quiescent or self.fd is None:
            raise GuardError("reader interlock cannot clear without confirmed owned-session quiescence")
        current = _no_symlink_path(self.path, "file")
        owned = os.fstat(self.fd)
        if (current.st_dev, current.st_ino, current.st_nlink) != (owned.st_dev, owned.st_ino, 1):
            raise GuardError("reader interlock identity changed; reconciliation required")
        self.path.unlink()
        _sync_directory(self.contract.state_dir)
        self.close()

    def close(self) -> None:
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None  # closing is never permission to remove the record


class OwnedChild:
    """The reader status plus an unreaped, exclusively owned session anchor.

    No Popen.poll/wait is allowed on the anchor before the last group signal.
    Its unreaped PID pins the PGID even if it dies first. After reaping, only
    signal-0 observations are allowed: a surviving/reused group stays blocked.
    """

    def __init__(self, process: subprocess.Popen, status_fd: int, control_fd: int) -> None:
        self.process = process
        self.status_fd = status_fd
        self.control_fd = control_fd
        self.status_bytes = b""
        self.status: int | None = None
        self.kill_sent = False
        self.reaped = False
        self.quiescent = False

    def poll(self) -> int | None:
        if self.quiescent:
            return self.status if self.status is not None else self.process.returncode
        if self.status is not None:
            return self.status
        try:
            chunk = os.read(self.status_fd, 65)
        except BlockingIOError:
            return None
        self.status_bytes += chunk
        if len(self.status_bytes) > 64 or (not chunk and b"\n" not in self.status_bytes):
            raise GuardError("reader session anchor lost its bounded status channel")
        if b"\n" not in self.status_bytes:
            return None
        try:
            text = self.status_bytes.decode("ascii")
            self.status = int(text)
            if text != f"{self.status}\n" or not -127 <= self.status <= 255:
                raise ValueError("invalid reader status")
        except (ValueError, UnicodeError) as exc:
            raise GuardError("reader session anchor could not report reader completion") from exc
        return self.status

    def _signal_group(self, number: int) -> None:
        if self.reaped or self.kill_sent:
            raise GuardError("refusing to signal a released reader group identity")
        # The direct anchor is still unreaped, not merely a matching PID sampled
        # from a process table. No other code waits for it or adopts its PGID.
        try:
            os.killpg(self.process.pid, number)
        except ProcessLookupError:
            pass  # still reap AND prove group absence before clearing anything

    def terminate(self) -> None:
        if not self.kill_sent and not self.quiescent:
            self._signal_group(signal.SIGTERM)

    def kill(self) -> None:
        if not self.kill_sent:
            self._signal_group(signal.SIGKILL)
            self.kill_sent = True  # seal signalling before any wait can reap

    def wait(self, timeout: float) -> int:
        if self.quiescent:
            return self.status if self.status is not None else self.process.returncode
        deadline = time.monotonic() + timeout
        if not self.kill_sent:
            # The TERM-resistant anchor intentionally remains until escalation;
            # a completed reader alone says nothing about its remaining helpers.
            time.sleep(timeout)
            raise TimeoutError("owned reader group requires final anchored cleanup")
        if not self.reaped:
            try:
                self.process.wait(timeout=max(0, deadline - time.monotonic()))
            except subprocess.TimeoutExpired as exc:
                raise TimeoutError("owned reader anchor did not exit") from exc
            self.reaped = True
        while True:
            try:
                os.killpg(self.process.pid, 0)
            except ProcessLookupError:
                self.quiescent = True
                self.close_channels()
                return self.status if self.status is not None else self.process.returncode
            if time.monotonic() >= deadline:
                raise TimeoutError("owned reader helpers are not confirmed quiescent")
            time.sleep(min(0.05, max(0, deadline - time.monotonic())))

    def shutdown(self) -> None:
        if self.quiescent:
            return
        try:
            self.terminate()
            try:
                self.wait(timeout=5)
            except TimeoutError:
                self.kill()
                self.wait(timeout=5)
        except (OSError, TimeoutError) as exc:
            raise GuardError("owned reader session cleanup unconfirmed; durable interlock retained") from exc

    def close_channels(self) -> None:
        for name in ("status_fd", "control_fd"):
            fd = getattr(self, name)
            if fd is not None:
                os.close(fd)
                setattr(self, name, None)


class ReaderLauncher:
    def __init__(self, config: RuntimeConfig) -> None:
        self.config = config
        self.child: OwnedChild | None = None
        self.interlock = RunInterlock(config.contract)
        self.navidrome_bytes = validate_navidrome(config)

    def start(self) -> OwnedChild:
        config = self.config
        if self.child is not None:
            raise GuardError("this supervisor never starts a second child")
        _no_symlink_path(config.binary, "file")
        if not os.access(config.binary, os.X_OK) or not os.access(SANDBOX, os.X_OK):
            raise GuardError("reviewed executable or macOS read-only sandbox is unavailable")
        digest = hashlib.sha256()
        fd = os.open(config.binary, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, "rb") as stream:
            while chunk := stream.read(1024 * 1024):
                digest.update(chunk)
        if digest.hexdigest() != config.binary_sha256:
            raise GuardError("installed reader differs from the reviewed non-purging binary")
        if validate_navidrome(config) != self.navidrome_bytes:
            raise GuardError("reader configuration changed before launch")
        # No shell, caller-supplied flags, ND_* overrides, credentials, writer
        # bootstrap or broad process-name kills. The sandbox's only writable
        # subtree is pre-existing derived state; it is NOT a media mkdir fallback.
        # Persist BOTH the file and directory before the first possible spawn.
        # Killing the supervisor can release flock but cannot release this gate.
        if signal.getsignal(signal.SIGCHLD) != signal.SIG_DFL:
            raise GuardError("owned-session cleanup requires the default, non-reaping SIGCHLD policy")
        verify_database_restore(config, admit=True)
        self.interlock.arm()
        status_read, status_write = os.pipe()
        control_read = control_write = None
        try:
            control_read, control_write = os.pipe()
            os.set_blocking(status_read, False)
            process = subprocess.Popen(
                [sys.executable, "-I", "-c", SESSION_ANCHOR, str(status_write), str(control_read),
                 SANDBOX, "-D", f"DATA={config.data_dir}", "-p", SANDBOX_PROFILE,
                 str(config.binary), "--configfile", str(config.navidrome_config)],
                stdin=subprocess.DEVNULL, close_fds=True, start_new_session=True,
                pass_fds=(status_write, control_read), cwd=config.data_dir,
                env={"PATH": "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C",
                     "HOME": "/var/empty", "TMPDIR": str(config.data_dir / "cache")},
            )
            self.child = OwnedChild(process, status_read, control_write)
        except BaseException:
            os.close(status_read)
            if control_write is not None:
                os.close(control_write)
            raise  # keep the durable interlock, including uncertain spawn failure
        finally:
            os.close(status_write)
            if control_read is not None:
                os.close(control_read)
        return self.child

    def finish(self) -> None:
        if self.child is not None:
            # ReaderGuard may see the primary reader's successful exit and skip
            # its Child._stop. Helpers/anchor still require independent cleanup.
            self.child.shutdown()
            self.interlock.clear_after_quiescence(self.child)

    def close(self) -> None:
        if self.child is not None:
            self.child.close_channels()
        self.interlock.close()


@contextmanager
def reader_lease(state_dir: Path):
    """One reader or explicit rearm at a time; never create state directories."""
    _private_directory(state_dir)
    fd = os.open(state_dir / "reader.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        entry = os.fstat(fd)
        if not stat.S_ISREG(entry.st_mode) or entry.st_uid != os.getuid() or stat.S_IMODE(entry.st_mode) & 0o077 or entry.st_nlink != 1:
            raise GuardError("reader lease file is not private and regular")
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise GuardError("another reader supervisor or rearm holds the lease") from exc
        _check_unclean_run(state_dir)
        yield
    finally:
        os.close(fd)


def run_reader(guard: ReaderGuard, launcher: ReaderLauncher, tick) -> int:
    """Turn normal supervisor stop signals into guarded shutdown, not an orphan."""
    signals = (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)
    previous = {number: signal.getsignal(number) for number in signals}

    pending_stop = []

    def interrupted(number, _frame):
        # Do not raise asynchronously between Popen and retaining its handle, or
        # during the guard's durable latch / owned-child shutdown sequence.
        if not pending_stop:
            pending_stop.append(number)

    def check_stop():
        if pending_stop:
            raise GuardError(f"reader supervisor interrupted by signal {pending_stop[0]}; manual rearm required")

    def start():
        check_stop()
        child = launcher.start()
        check_stop()
        return child

    def guarded_tick():
        check_stop()
        tick()
        check_stop()

    try:
        for number in signals:
            signal.signal(number, interrupted)
        return guard.run_once(start, guarded_tick)
    finally:
        try:
            launcher.finish()
        finally:
            launcher.close()  # failure closes FDs, never clears the interlock
            for number, handler in previous.items():
                signal.signal(number, handler)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("verify", "run", "rearm"))
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--confirm-epoch")
    args = parser.parse_args()
    try:
        config = load_config(_path(str(args.config)))
        if (args.operation == "rearm") != (args.confirm_epoch is not None):
            raise GuardError("only explicit rearm accepts and requires --confirm-epoch")
        guard = PublishedE1Guard(config.contract, observer.observe_host,
                                 observer.MacOSVolumeObserver(config.contract.mountpoint))
        with reader_lease(config.contract.state_dir):
            launcher = ReaderLauncher(config)
            if args.operation == "rearm":
                verify_database_restore(config)
                guard.rearm_manually(lambda: args.confirm_epoch == config.contract.epoch)
                return 0  # rearm never starts a child
            if args.operation == "verify":
                guard.verify()
                verify_database_restore(config)
                return 0
            status = run_reader(guard, launcher, lambda: time.sleep(config.poll_seconds))
            return status if 0 <= status <= 125 else 1
    except (GuardError, OSError, ValueError, TypeError) as exc:
        print(f"MBA reader refused: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
