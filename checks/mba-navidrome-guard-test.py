"""Synthetic, offline NV01/NV02 guard tests; no real mounts or Navidrome."""

import hashlib
import importlib.util
import json
import os
import plistlib
import sqlite3
import stat
import subprocess
import sys
import tempfile
import unittest
from contextlib import closing, contextmanager
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

SOURCE = Path(__file__).resolve().parents[1] / "rig/bootstrap/mba-navidrome/guard.py"
SPEC = importlib.util.spec_from_file_location("mba_navidrome_guard", SOURCE)
assert SPEC is not None and SPEC.loader is not None
module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = module
SPEC.loader.exec_module(module)
RUN_SPEC = importlib.util.spec_from_file_location("mba_navidrome_runner", SOURCE.parent / "run-guarded.py")
assert RUN_SPEC is not None and RUN_SPEC.loader is not None
runner = importlib.util.module_from_spec(RUN_SPEC)
sys.modules[RUN_SPEC.name] = runner
RUN_SPEC.loader.exec_module(runner)

UUID = "01234567-89ab-cdef-0123-456789abcdef"
OTHER_UUID = "01234567-89ab-cdef-0123-456789abcdea"


class SyntheticChild:
    def __init__(self):
        self.exit_code = None
        self.terminations = 0
        self.kills = 0

    def poll(self):
        return self.exit_code

    def terminate(self):
        self.terminations += 1
        self.exit_code = -15

    def wait(self, timeout):
        return self.exit_code

    def kill(self):
        self.kills += 1
        self.exit_code = -9


class SyntheticSession:
    """No processes/signals: model a pinned anchor, reader and same-group helpers."""

    def __init__(self, helpers=(), *, helpers_survive_kill=False):
        self.pid = 424242
        self.reader = SyntheticChild()
        self.helpers = list(helpers)
        self.helpers_survive_kill = helpers_survive_kill
        self.returncode = None
        self.reaped = False
        self.terminations = 0
        self.kills = 0
        self.events = []
        self.status_fd = None
        self.on_spawn = None

    def spawn(self, argv, **kwargs):
        self.status_fd = os.dup(int(argv[4]))
        self.events.append("spawn")
        if self.on_spawn is not None:
            self.on_spawn()
        return self

    def report(self, status):
        self.reader.exit_code = status
        if self.status_fd is not None:
            os.write(self.status_fd, f"{status}\n".encode("ascii"))
            self.close_status()

    def close_status(self):
        if self.status_fd is not None:
            os.close(self.status_fd)
            self.status_fd = None

    def poll(self):
        raise AssertionError("polling/reaping the anchor would release its group identity")

    def signal_group(self, pgid, number):
        if pgid != self.pid:
            raise AssertionError("attempt to signal an unrelated group")
        self.events.append(("signal", number))
        if number == 0:
            if self.returncode is None or any(child.poll() is None for child in self.helpers):
                return
            raise ProcessLookupError("synthetic group is empty")
        if self.reaped:
            raise AssertionError("group signal after reaping permits PGID reuse")
        if number == runner.signal.SIGTERM:
            self.terminations += 1
            if self.reader.poll() is None:
                self.report(-15)
            # Model helpers which ignore TERM; the anchor also deliberately stays.
        elif number == runner.signal.SIGKILL:
            self.kills += 1
            self.returncode = -9
            if self.reader.poll() is None:
                self.reader.kill()
            if not self.helpers_survive_kill:
                for child in self.helpers:
                    if child.poll() is None:
                        child.kill()
        else:
            raise AssertionError("unexpected synthetic group signal")

    def wait(self, timeout):
        self.events.append("reap")
        if self.kills != 1:
            raise AssertionError("anchor was reaped before final group-wide KILL")
        if self.returncode is None:
            raise subprocess.TimeoutExpired("synthetic-anchor", timeout)
        self.reaped = True
        return self.returncode


class ReaderGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.mount = self.base / "Volumes" / "ApprovedMedia"
        self.root = self.mount / "Published-E0"
        self.root.mkdir(parents=True)
        self.state = self.base / "persistent-state"
        self.state.mkdir()
        self.song = self.root / "artist" / "song.flac"
        self.song.parent.mkdir()
        self.song.write_bytes(b"synthetic audio bytes")
        self.witness = self.mount / ".e0-witness.json"
        self.publish_witness()
        self.contract = module.ReaderContract(
            hostname="mba-approved.example",
            apfs_uuid=UUID,
            mountpoint=self.mount,
            media_root=self.root,
            witness=self.witness,
            epoch="closed-e0-manifest-id",
            state_dir=self.state,
        )
        self.host = "mba-approved.example"
        self.volume = module.VolumeIdentity(UUID, self.mount, "apfs")

    def publish_witness(self, **changes):
        import hashlib

        files = [p for p in self.root.rglob("*") if p.is_file()]
        payload = {
            "epoch": "closed-e0-manifest-id",
            "file_count": len(files),
            "total_bytes": sum(p.stat().st_size for p in files),
            "sample": {
                "path": "artist/song.flac",
                "sha256": hashlib.sha256(self.song.read_bytes()).hexdigest(),
            },
        }
        payload.update(changes)
        self.witness.write_text(json.dumps(payload), encoding="utf-8")

    def guard(self, contract=None):
        return module.ReaderGuard(
            contract or self.contract,
            lambda: self.host,
            lambda _mountpoint: self.volume,
        )

    def assert_blocked_before_spawn(self):
        launched = []
        with self.assertRaises(module.GuardError):
            self.guard().run_once(
                lambda: launched.append(SyntheticChild()), lambda: None
            )
        self.assertEqual(launched, [])

    def test_preflight_requires_matching_configured_host(self):
        self.host = "not-approved"
        self.assert_blocked_before_spawn()
        self.host = "mba-approved.example"
        self.assertEqual(self.guard().verify(), None)

    def test_preflight_requires_actual_apfs_uuid_and_mountpoint(self):
        for observed in (
            None,
            module.VolumeIdentity(OTHER_UUID, self.mount, "apfs"),
            module.VolumeIdentity(UUID, self.base / "elsewhere", "apfs"),
            module.VolumeIdentity(UUID, self.mount, "hfs"),
        ):
            with self.subTest(observed=observed):
                self.volume = observed
                self.assert_blocked_before_spawn()
        self.volume = module.VolumeIdentity(UUID, self.mount, "apfs")
        self.guard().verify()

    def test_invalid_or_unconfigured_contract_rejected(self):
        for changed in (
            {"hostname": ""},
            {"apfs_uuid": "UNCONFIGURED"},
            {"mountpoint": Path("/")},
            {"media_root": self.base / "outside"},
            {"state_dir": self.mount / "volatile-state"},
            {"witness": self.root / "witness.json"},
        ):
            with self.subTest(changed=changed), self.assertRaises(module.GuardError):
                self.guard(replace(self.contract, **changed))

    def test_published_nonempty_witness_and_matching_census_required(self):
        self.publish_witness(file_count=0)
        self.assert_blocked_before_spawn()
        self.publish_witness(total_bytes=0)
        self.assert_blocked_before_spawn()
        self.publish_witness(epoch="other-epoch")
        self.assert_blocked_before_spawn()
        self.publish_witness()
        self.song.unlink()
        self.assert_blocked_before_spawn()

    def test_root_fallback_after_mount_loss_is_not_accepted(self):
        self.volume = None
        self.assert_blocked_before_spawn()  # stale-looking directory still exists

    def test_sample_path_escape_or_wrong_hash_blocked(self):
        self.publish_witness(sample={"path": "../outside.flac", "sha256": "0" * 64})
        self.assert_blocked_before_spawn()
        self.publish_witness(sample={"path": "artist/song.flac", "sha256": "0" * 64})
        self.assert_blocked_before_spawn()

    def test_nested_symlink_escape_blocked_without_following(self):
        outside = self.base / "outside.flac"
        outside.write_bytes(b"not media")
        (self.root / "escape.flac").symlink_to(outside)
        self.assert_blocked_before_spawn()
        (self.root / "escape.flac").unlink()
        self.root.rename(self.mount / "Real-E0")
        self.root.symlink_to(self.mount / "Real-E0", target_is_directory=True)
        self.assert_blocked_before_spawn()

    def test_abrupt_running_loss_stops_child_and_persists_latch(self):
        launched = []

        def start():
            child = SyntheticChild()
            launched.append(child)
            return child

        def lose_mount():
            self.volume = None

        guard = self.guard()
        with self.assertRaisesRegex(module.GuardError, "actual APFS"):
            guard.run_once(start, lose_mount)
        self.assertEqual(len(launched), 1)
        self.assertEqual(launched[0].terminations, 1)
        self.assertEqual(launched[0].kills, 0)
        latch = json.loads(guard.latch_path.read_text(encoding="utf-8"))
        self.assertEqual(latch["epoch"], self.contract.epoch)
        self.volume = module.VolumeIdentity(UUID, self.mount, "apfs")
        self.assert_blocked_before_spawn()  # remount cannot automatically rearm
        self.assertEqual(len(launched), 1)

    def test_running_witness_loss_also_latches_and_stops(self):
        child = SyntheticChild()

        def lose_witness():
            self.witness.unlink()

        with self.assertRaises(module.GuardError):
            self.guard().run_once(lambda: child, lose_witness)
        self.assertEqual(child.terminations, 1)
        self.assertTrue(self.guard().latch_path.is_file())

    def test_running_observer_error_latches_and_stops(self):
        child = SyntheticChild()
        guard = self.guard()

        def unavailable(_mountpoint):
            raise OSError("synthetic observer unavailable")

        def lose_observer():
            guard.observe_mount = unavailable

        with self.assertRaisesRegex(module.GuardError, "observer failed"):
            guard.run_once(lambda: child, lose_observer)
        self.assertEqual(child.terminations, 1)
        self.assertTrue(guard.latch_path.is_file())

    def test_existing_or_unreadable_latch_blocks_even_after_restart(self):
        self.guard().latch_path.write_text("not even valid JSON", encoding="utf-8")
        self.assert_blocked_before_spawn()
        self.guard().latch_path.unlink()
        self.guard().latch_path.symlink_to(self.witness)
        self.assert_blocked_before_spawn()

    def test_internal_data_volume_accepts_latch_outside_media_tree(self):
        self.state.rmdir()
        self.state = self.mount / "guard-state"
        self.state.mkdir()
        contract = replace(self.contract, topology="internal-data", state_dir=self.state)
        self.volume = module.VolumeIdentity(UUID, self.mount, "apfs", "Data", True)
        self.guard(contract).verify()
        self.assertEqual(self.guard(contract).latch_path.parent, self.state)
        for changed in (
            {"state_dir": self.root / "subdir"},
            {"state_dir": self.mount},
            {"state_dir": self.base / "off-data-volume"},
            {"media_root": self.base / "off-data-volume"},
            {"topology": "unrecognized"},
        ):
            with self.subTest(changed=changed), self.assertRaises(module.GuardError):
                self.guard(replace(contract, **changed))

    def test_internal_data_identity_and_path_observation_fail_closed(self):
        self.state.rmdir()
        self.state = self.mount / "guard-state"
        self.state.mkdir()
        contract = replace(self.contract, topology="internal-data", state_dir=self.state)
        approved = module.VolumeIdentity(UUID, self.mount, "apfs", "Data", True)
        guard = self.guard(contract)
        for observed in (
            None,
            module.VolumeIdentity(OTHER_UUID, self.mount, "apfs", "Data", True),
            module.VolumeIdentity(UUID, self.mount, "apfs", "Data", False),
            module.VolumeIdentity(UUID, self.mount, "apfs", "System", True),
            module.VolumeIdentity(UUID, self.base, "apfs", "Data", True),
        ):
            with self.subTest(observed=observed), self.assertRaises(module.GuardError):
                self.volume = observed
                guard.verify()
        self.volume = approved
        guard.verify()
        for path in (self.mount, self.root, self.witness, self.state):
            with self.subTest(path=path):
                guard.observe_mount = lambda p, target=path: (
                    None if p == target else approved
                )
                with self.assertRaises(module.GuardError):
                    guard.verify()
                guard.observe_mount = lambda p, target=path: (
                    module.VolumeIdentity(OTHER_UUID, self.mount, "apfs", "Data", True)
                    if p == target else approved
                )
                with self.assertRaises(module.GuardError):
                    guard.verify()
        guard.observe_mount = None  # missing observer is not inferred from files
        with self.assertRaises(module.GuardError):
            guard.verify()

    def test_internal_data_symlink_and_root_drift_fail_closed(self):
        self.state.rmdir()
        self.state = self.mount / "guard-state"
        self.state.mkdir()
        contract = replace(self.contract, topology="internal-data", state_dir=self.state)
        self.volume = module.VolumeIdentity(UUID, self.mount, "apfs", "Data", True)
        guard = self.guard(contract)
        guard.verify()
        self.state.rename(self.mount / "real-guard-state")
        self.state.symlink_to(self.mount / "real-guard-state", target_is_directory=True)
        with self.assertRaises(module.GuardError):
            guard.verify()
        self.state.unlink()
        (self.mount / "real-guard-state").rename(self.state)
        self.root.rename(self.mount / "other-root")
        with self.assertRaises(module.GuardError):
            guard.verify()
        self.root.symlink_to(self.mount / "other-root", target_is_directory=True)
        with self.assertRaises(module.GuardError):
            guard.verify()

    def test_external_fixture_still_rejects_data_role_and_on_mount_latch(self):
        self.volume = module.VolumeIdentity(UUID, self.mount, "apfs", "Data", True)
        self.assert_blocked_before_spawn()
        self.volume = module.VolumeIdentity(UUID, self.mount, "apfs")
        with self.assertRaises(module.GuardError):
            self.guard(replace(self.contract, state_dir=self.mount / "guard-state"))
        self.guard().verify()

    def test_e1_stops_and_disables_before_demotion_and_remains_latched(self):
        child = SyntheticChild()
        events = []
        guard = self.guard()

        def disable():
            self.assertEqual(child.terminations, 1)
            self.assertIsNotNone(child.poll())
            self.assertTrue(guard.latch_path.is_file())
            events.append("disable")
            return True

        def demote():
            self.assertEqual(events, ["disable"])
            self.assertIsNotNone(child.poll())
            self.assertTrue(guard.latch_path.is_file())
            events.append("demote")

        guard.transition_to_e1(child, disable, demote)
        self.assertEqual(events, ["disable", "demote"])
        self.assert_blocked_before_spawn()
        with self.assertRaisesRegex(module.GuardError, "newly published epoch"):
            guard.rearm_manually(lambda: True)
        self.publish_witness(epoch="closed-e1-manifest-id")
        new_contract = replace(self.contract, epoch="closed-e1-manifest-id")
        new_guard = self.guard(new_contract)
        with self.assertRaisesRegex(module.GuardError, "positively verified"):
            new_guard.rearm_manually(lambda: False)
        self.assertTrue(guard.latch_path.is_file())
        new_guard.rearm_manually(lambda: True)
        new_guard.verify()
        self.assertFalse(guard.latch_path.exists())

    def test_e1_incomplete_never_demotes_or_auto_rearms(self):
        for disabled in (False, None):
            with self.subTest(disabled=disabled):
                child = SyntheticChild()
                guard = self.guard()
                demotions = []
                with self.assertRaisesRegex(module.GuardError, "not positively disabled"):
                    guard.transition_to_e1(child, lambda: disabled, lambda: demotions.append(1))
                self.assertEqual(child.terminations, 1)
                self.assertEqual(demotions, [])
                self.assert_blocked_before_spawn()
                guard.latch_path.unlink()  # synthetic fixture reset only
        child = SyntheticChild()
        guard = self.guard()
        with self.assertRaisesRegex(module.GuardError, "demotion incomplete"):
            guard.transition_to_e1(child, lambda: True, lambda: (_ for _ in ()).throw(RuntimeError()))
        self.assertTrue(guard.latch_path.is_file())
        self.assert_blocked_before_spawn()

    def test_e1_identity_drift_after_disable_prohibits_demotion(self):
        child = SyntheticChild()
        guard = self.guard()
        demotions = []

        def disable_and_drift():
            self.volume = module.VolumeIdentity(OTHER_UUID, self.mount, "apfs")
            return True

        with self.assertRaisesRegex(module.GuardError, "actual APFS"):
            guard.transition_to_e1(child, disable_and_drift, lambda: demotions.append(1))
        self.assertEqual(child.terminations, 1)
        self.assertEqual(demotions, [])
        self.assertTrue(guard.latch_path.is_file())

    def test_malformed_latch_cannot_be_manually_rearmed(self):
        guard = self.guard()
        guard.latch_path.write_text('{"reason":"e1-incomplete: test"}', encoding="utf-8")
        with self.assertRaisesRegex(module.GuardError, "malformed"):
            guard.rearm_manually(lambda: True)
        self.assert_blocked_before_spawn()

    def test_e1_unconfirmed_shutdown_prohibits_demotion(self):
        class Unstoppable(SyntheticChild):
            def terminate(self):
                self.terminations += 1

            def wait(self, timeout):
                return 0  # claimed completion without exited process

        child = Unstoppable()
        guard = self.guard()
        callbacks = []
        with self.assertRaisesRegex(module.GuardError, "shutdown was not confirmed"):
            guard.transition_to_e1(child, lambda: callbacks.append("disable"),
                                   lambda: callbacks.append("demote"))
        self.assertEqual(callbacks, [])
        self.assert_blocked_before_spawn()

    def test_reader_crash_and_start_failure_latch_against_restart(self):
        child = SyntheticChild()

        def crash():
            child.exit_code = 23

        guard = self.guard()
        self.assertEqual(guard.run_once(lambda: child, crash), 23)
        self.assertTrue(guard.latch_path.is_file())
        self.assert_blocked_before_spawn()
        guard.latch_path.unlink()  # synthetic fixture reset only
        with self.assertRaisesRegex(module.GuardError, "reader start failed"):
            guard.run_once(lambda: (_ for _ in ()).throw(RuntimeError()), lambda: None)
        self.assert_blocked_before_spawn()

    def test_mba_reader_configuration_remains_blocked(self):
        source_dir = SOURCE.parent
        placeholder = source_dir / "navidrome.toml.BLOCKED"
        text = placeholder.read_text(encoding="utf-8")
        self.assertIn("INTENTIONALLY NOT A NAVIDROME CONFIGURATION", text)
        self.assertIn("Scanner.PurgeMissing: supported non-purging value UNKNOWN", text)
        self.assertFalse((source_dir / "navidrome.toml").exists())
        self.assertEqual(list(source_dir.glob("*.plist*")), [])

    def production_config(self, topology="external-dedicated"):
        """Render only inside this disposable fixture; never invoke a reader."""
        self.state.chmod(0o700)
        derived = (self.mount if topology == "internal-data" else self.base) / "reader-data"
        derived.mkdir(mode=0o700)
        (derived / "cache").mkdir(mode=0o700)
        binary = self.base / "fixture-navidrome"
        binary.write_bytes(b"synthetic reviewed executable; never executed")
        binary.chmod(0o700)
        nav_config = self.base / "reader.toml"
        template = (SOURCE.parent / "navidrome.toml.tmpl").read_text(encoding="utf-8")
        nav_config.write_text(template.replace("__MBA_PUBLISHED_E1_MEDIA_ROOT__", str(self.root))
                              .replace("__MBA_NAVIDROME_DATA_DIR__", str(derived)), encoding="utf-8")
        nav_config.chmod(0o600)
        database = derived / "navidrome.db"
        connection = sqlite3.connect(database)
        connection.executescript("""
            CREATE TABLE user(id TEXT PRIMARY KEY);
            CREATE TABLE playlist(id TEXT PRIMARY KEY);
            CREATE TABLE playlist_tracks(id INTEGER PRIMARY KEY,playlist_id TEXT,media_file_id TEXT);
            CREATE TABLE annotation(user_id TEXT,item_id TEXT,item_type TEXT,play_count INTEGER);
            CREATE TABLE media_file(id TEXT PRIMARY KEY,path TEXT);
            CREATE TABLE folder(id TEXT PRIMARY KEY,path TEXT);
            CREATE TABLE library(id INTEGER PRIMARY KEY,path TEXT);
            CREATE TABLE album(id TEXT PRIMARY KEY);
            CREATE TABLE artist(id TEXT PRIMARY KEY);
            CREATE TABLE bookmark(id TEXT PRIMARY KEY);
            CREATE TABLE playqueue(id TEXT PRIMARY KEY);
            CREATE TABLE property(id TEXT PRIMARY KEY);
            INSERT INTO user VALUES('fixture-user');
            INSERT INTO playlist VALUES('fixture-playlist');
            INSERT INTO playlist_tracks VALUES(1,'fixture-playlist','fixture-track');
            INSERT INTO annotation VALUES('fixture-user','fixture-track','media_file',7);
            INSERT INTO media_file VALUES('fixture-track','artist/song.flac');
            INSERT INTO folder VALUES('fixture-folder','artist');
            INSERT INTO library VALUES(1,'/fixture/source-root');
        """)
        connection.close()
        database.chmod(0o600)
        expected_database = runner.restored_database_metadata(database)
        export = self.base / "support-export.json"
        export.write_text(json.dumps({"schema": "mba-music-selected-support-export-v1",
            "source_unchanged": True, "host_paths_rewritten": False,
            "files": [{"key": "navidrome-navidrome-db", "sha256": expected_database["sha256"],
                       "database": {"schema_sha256": expected_database["schema_sha256"],
                                    "selected_table_counts": expected_database["selected_table_counts"]}}]}))
        backup = self.base / "backup-proof.json"
        backup.write_text('{"fixture":"completed-independent-backup"}')
        restored = self.base / "restore-proof.json"
        restored.write_text('{"fixture":"completed-fresh-readonly-restore"}')
        for proof in (export, backup, restored):
            proof.chmod(0o600)
        reference = lambda p: {"path": str(p), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
        restore_witness = self.base / "native-restore.json"
        restore_witness.write_text(json.dumps({"schema_version": 1, "source_reader_quiesced": True,
            "independent_backup_verified": True, "independent_restore_verified": True,
            "support_export": reference(export), "backup_receipt": reference(backup),
            "restore_receipt": reference(restored), "native_version": "fixture-native-version",
            "database": expected_database}))
        restore_witness.chmod(0o600)
        raw = {
            "schema_version": 1, "publication_state": "E1", "hostname": self.host,
            "apfs_uuid": UUID, "mountpoint": str(self.mount), "media_root": str(self.root),
            "witness": str(self.witness), "epoch": "closed-e1-fixture", "state_dir": str(self.state),
            "topology": topology, "binary": str(binary),
            "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
            "navidrome_config": str(nav_config), "data_dir": str(derived),
            "address": "127.0.0.1", "port": 4533, "poll_seconds": 5,
            "native_version": "fixture-native-version", "restore_witness": str(restore_witness),
            "restore_witness_sha256": hashlib.sha256(restore_witness.read_bytes()).hexdigest(),
        }
        path = self.base / "reader.json"
        path.write_text(json.dumps(raw), encoding="utf-8")
        path.chmod(0o600)
        self.publish_witness(epoch=raw["epoch"], publication_state="E1", media_root=str(self.root))
        return path, raw, runner.load_config(path)

    def production_guard(self, config):
        return runner.PublishedE1Guard(config.contract, lambda: self.host, lambda _path: self.volume)

    @contextmanager
    def production_session(self, process=None):
        process = process or SyntheticSession()
        self.addCleanup(process.close_status)
        clock = [0]

        def monotonic():
            clock[0] += 0.5
            return clock[0]

        with patch.object(runner.os, "access", return_value=True), \
             patch.object(runner.subprocess, "run", return_value=SimpleNamespace(
                 returncode=0, stdout=b"fixture-native-version\n", stderr=b"")), \
             patch.object(runner.subprocess, "Popen", side_effect=process.spawn) as spawn, \
             patch.object(runner.os, "killpg", side_effect=process.signal_group), \
             patch.object(runner.time, "sleep"), \
             patch.object(runner.time, "monotonic", side_effect=monotonic):
            process.spawn_mock = spawn
            yield process

    def admit_fixture_restore(self, config):
        with patch.object(runner.subprocess, "run", return_value=SimpleNamespace(
                returncode=0, stdout=b"fixture-native-version\n", stderr=b"")):
            runner.verify_database_restore(config, admit=True)

    def test_fresh_database_refused_before_any_reader_spawn(self):
        _path, _raw, config = self.production_config()
        with closing(sqlite3.connect(config.data_dir / "navidrome.db")) as connection, connection:
            connection.execute("DELETE FROM user")
            connection.execute("DELETE FROM media_file")
        launcher = runner.ReaderLauncher(config)
        with self.production_session() as process, self.assertRaisesRegex(module.GuardError, "reader start failed") as error:
            runner.run_reader(self.production_guard(config), launcher, lambda: None)
        self.assertIn("restored database requires", str(error.exception.__cause__))
        process.spawn_mock.assert_not_called()
        self.assertFalse((self.state / runner.RESTORE_ADMISSION).exists())

    def test_matching_restore_admits_once_without_claiming_native_start(self):
        _path, _raw, config = self.production_config()
        self.admit_fixture_restore(config)
        admission = self.state / runner.RESTORE_ADMISSION
        before = admission.read_bytes()
        self.assertEqual(json.loads(before)["state"], "restoration-admitted-not-native-start-proof")
        # Legitimate native playcount/playlist writes need not match a stale full hash.
        with closing(sqlite3.connect(config.data_dir / "navidrome.db")) as connection, connection:
            connection.execute("UPDATE annotation SET play_count=8")
            connection.execute("INSERT INTO playlist VALUES('new-native-playlist')")
        self.admit_fixture_restore(config)
        self.assertEqual(admission.read_bytes(), before)
        self.assertFalse((self.state / runner.UNCLEAN_RUN).exists())
        wal = Path(str(config.data_dir / "navidrome.db") + "-wal")
        wal.touch()
        wal.chmod(0o600)
        with self.assertRaisesRegex(module.GuardError, "without creating"):
            runner.verify_database_restore(config)
        self.assertFalse(Path(str(config.data_dir / "navidrome.db") + "-shm").exists())

    def test_internal_restore_admission_survives_only_same_volume_and_inode(self):
        self.state = self.mount / "persistent-state"
        self.state.mkdir(mode=0o700)
        _path, _raw, config = self.production_config("internal-data")
        database = config.data_dir / "navidrome.db"
        volume = module.VolumeIdentity(UUID, self.mount, "apfs", "Data", True)
        with patch.object(runner.observer, "MacOSVolumeObserver", return_value=lambda _path: volume):
            self.admit_fixture_restore(config)
        admission = self.state / runner.RESTORE_ADMISSION
        before = admission.read_bytes()
        recorded = json.loads(before)
        self.assertEqual(recorded["schema_version"], 2)
        self.assertEqual(recorded["database_identity"], {"volume_uuid": UUID, "inode": database.stat().st_ino})
        actual_stat = runner._no_symlink_path

        def boot_stat(path, kind):
            entry = actual_stat(path, kind)
            if path == database:
                return SimpleNamespace(**{name: (entry.st_dev + 1 if name == "st_dev" else getattr(entry, name))
                                          for name in dir(entry) if name.startswith("st_")})
            return entry

        with patch.object(runner.observer, "MacOSVolumeObserver", return_value=lambda _path: volume), \
             patch.object(runner, "_no_symlink_path", side_effect=boot_stat):
            self.admit_fixture_restore(config)
        self.assertEqual(admission.read_bytes(), before)
        for observed in (module.VolumeIdentity(OTHER_UUID, self.mount, "apfs", "Data", True),
                         module.VolumeIdentity(UUID, self.mount, "apfs", "", True),
                         module.VolumeIdentity(UUID, self.mount, "apfs", "Data", False)):
            with self.subTest(volume=observed), \
                 patch.object(runner.observer, "MacOSVolumeObserver", return_value=lambda _path: observed), \
                 self.assertRaisesRegex(module.GuardError, "pinned internal Data volume"):
                self.admit_fixture_restore(config)
        original = self.base / "original-admitted.sqlite3"
        database.rename(original)
        database.write_bytes(original.read_bytes())
        database.chmod(0o600)
        with patch.object(runner.observer, "MacOSVolumeObserver", return_value=lambda _path: volume), \
             self.assertRaisesRegex(module.GuardError, "identity or prior restoration"):
            self.admit_fixture_restore(config)
        self.assertEqual(admission.read_bytes(), before)

    def test_changed_database_witness_and_native_version_refused(self):
        _path, _raw, config = self.production_config()
        database = config.data_dir / "navidrome.db"
        original = database.read_bytes()
        with closing(sqlite3.connect(database)) as connection, connection:
            connection.execute("UPDATE user SET id='different-restored-identity'")
        with self.assertRaisesRegex(module.GuardError, "hash, counts or native identities"):
            runner.verify_database_restore(config)
        database.write_bytes(original)
        proof = config.restore_witness.read_bytes()
        config.restore_witness.write_bytes(proof + b"\n")
        with self.assertRaisesRegex(module.GuardError, "witness changed"):
            runner.verify_database_restore(config)
        config.restore_witness.write_bytes(proof)
        with patch.object(runner.subprocess, "run", return_value=SimpleNamespace(
                returncode=0, stdout=b"other-native-version\n", stderr=b"")), \
             self.assertRaisesRegex(module.GuardError, "native version differs"):
            runner.verify_database_restore(config)
        self.assertFalse((self.state / runner.RESTORE_ADMISSION).exists())

    def test_admitted_sqlite_sidecars_cannot_follow_links_outside_data(self):
        _path, _raw, config = self.production_config()
        self.admit_fixture_restore(config)
        outside = self.base / "outside-sidecar"
        outside.write_bytes(b"unrelated fixture bytes")
        before = outside.stat()
        database = config.data_dir / "navidrome.db"
        for suffix in ("-wal", "-shm", "-journal"):
            sidecar = Path(str(database) + suffix)
            sidecar.symlink_to(outside)
            with self.subTest(suffix=suffix), self.assertRaisesRegex(module.GuardError, "symlink"):
                runner.verify_database_restore(config)
            sidecar.unlink()
        self.assertEqual(outside.read_bytes(), b"unrelated fixture bytes")
        after = outside.stat()
        self.assertEqual((after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns),
                         (before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns))

    def test_admitted_database_replacement_and_truncation_refused(self):
        _path, _raw, config = self.production_config()
        self.admit_fixture_restore(config)
        database = config.data_dir / "navidrome.db"
        original = self.base / "original-admitted.sqlite3"
        database.rename(original)
        database.write_bytes(original.read_bytes())
        database.chmod(0o600)
        with self.assertRaisesRegex(module.GuardError, "identity or prior restoration"):
            runner.verify_database_restore(config)
        database.unlink()
        original.rename(database)
        database.write_bytes(b"")
        with self.assertRaisesRegex(module.GuardError, "unreadable"):
            runner.verify_database_restore(config)

    def os_metadata(self):
        info = {
            "Mounted": True, "MountPoint": str(self.mount), "FilesystemType": "apfs",
            "Internal": False, "DeviceIdentifier": "disk7s2", "DeviceNode": "/dev/disk7s2",
            "APFSContainerReference": "disk7", "VolumeUUID": UUID,
        }
        apfs = {"Containers": [{"ContainerReference": "disk7", "Volumes": [{
            "DeviceIdentifier": "disk7s2", "APFSVolumeUUID": UUID,
            "MountPoint": str(self.mount), "Roles": [],
        }]}]}
        return info, apfs

    def test_operator_config_requires_explicit_e1_private_state_and_nonwildcard_bind(self):
        path, raw, _config = self.production_config()
        for change in (
            {"publication_state": "E0"}, {"address": "0.0.0.0"}, {"address": "::"},
            {"port": True}, {"poll_seconds": 0}, {"hostname": ""},
            {"media_root": str(self.root / ".." / "other")},
            {"data_dir": str(self.mount)}, {"data_dir": str(self.state / "derived")},
            {"restore_witness": str(self.root / "scanned-proof.json")},
            {"topology": "guessed"}, {"binary_sha256": "unreviewed"},
        ):
            with self.subTest(change=change):
                path.write_text(json.dumps({**raw, **change}), encoding="utf-8")
                with self.assertRaises(module.GuardError):
                    runner.load_config(path)
        path.write_text(json.dumps(raw), encoding="utf-8")
        path.chmod(0o644)
        with self.assertRaisesRegex(module.GuardError, "private"):
            runner.load_config(path)
        path.chmod(0o600)
        (Path(raw["data_dir"]) / "cache").rmdir()
        with self.assertRaises(module.GuardError):
            runner.load_config(path)
        self.assertFalse((Path(raw["data_dir"]) / "cache").exists())

    def test_production_internal_data_contract_keeps_derived_and_guard_state_separate(self):
        path, raw, config = self.production_config()
        moved_state = self.mount / "guard-state"
        self.state.rename(moved_state)
        self.state = moved_state
        moved_data = self.mount / "reader-data"
        config.data_dir.rename(moved_data)
        raw.update(topology="internal-data", state_dir=str(moved_state), data_dir=str(moved_data))
        path.write_text(json.dumps(raw), encoding="utf-8")
        config.navidrome_config.write_text(
            config.navidrome_config.read_text(encoding="utf-8").replace(str(config.data_dir), str(moved_data)),
            encoding="utf-8",
        )
        config = runner.load_config(path)
        self.volume = module.VolumeIdentity(UUID, self.mount, "apfs", "Data", True)
        self.production_guard(config).verify()
        for observed in (
            module.VolumeIdentity(UUID, self.mount, "apfs", "Data", False),
            module.VolumeIdentity(UUID, self.mount, "apfs", "System", True),
        ):
            self.volume = observed
            start = Mock()
            with self.subTest(observed=observed), self.assertRaises(module.GuardError):
                self.production_guard(config).run_once(start, lambda: None)
            start.assert_not_called()

    def test_mba_template_policy_must_match_the_operator_contract_exactly(self):
        _path, _raw, config = self.production_config()
        original = config.navidrome_config.read_text(encoding="utf-8")
        runner.validate_navidrome(config)
        for before, after in (
            ("PurgeMissing = 'never'", "PurgeMissing = 'always'"),
            ("Address = '127.0.0.1'", "Address = '0.0.0.0'"),
            (str(self.root), str(self.base / "wrong-tree")),
            ("EnableSharing = false", "EnableSharing = 0"),
        ):
            with self.subTest(after=after):
                config.navidrome_config.write_text(original.replace(before, after), encoding="utf-8")
                with self.assertRaises(module.GuardError):
                    runner.validate_navidrome(config)

    def test_e1_witness_phase_tree_and_epoch_cannot_be_inferred_from_config(self):
        _path, _raw, config = self.production_config()
        start = Mock()
        for changes in (
            {"publication_state": "E0"}, {"publication_state": "E1-incomplete"},
            {"media_root": str(self.mount / "other-published-tree")}, {"epoch": "unpublished"},
        ):
            with self.subTest(changes=changes):
                self.publish_witness(epoch=config.contract.epoch, publication_state="E1", media_root=str(self.root))
                witness = json.loads(self.witness.read_text(encoding="utf-8"))
                witness.update(changes)
                self.witness.write_text(json.dumps(witness), encoding="utf-8")
                with self.assertRaises(module.GuardError):
                    self.production_guard(config).run_once(start, lambda: None)
        start.assert_not_called()

    def test_os_observer_uses_targeted_plists_and_device_identity(self):
        info, apfs = self.os_metadata()
        adapter = runner.observer.MacOSVolumeObserver(self.mount)
        node = SimpleNamespace(st_mode=stat.S_IFBLK, st_rdev=self.mount.stat().st_dev)
        with patch.object(runner.observer.sys, "platform", "darwin"), \
             patch.object(runner.observer, "_device_stat", return_value=node), \
             patch.object(runner.observer, "_diskutil_plist", side_effect=[info, apfs]) as metadata:
            observed = adapter(self.song)
        self.assertEqual(observed, module.VolumeIdentity(UUID, self.mount, "apfs", "", False))
        self.assertEqual(metadata.call_args_list[0].args[0], ["info", "-plist", str(self.mount)])
        self.assertEqual(metadata.call_args_list[1].args[0], ["apfs", "list", "-plist", "disk7"])
        info["Internal"] = True
        apfs["Containers"][0]["Volumes"][0]["Roles"] = ["Data"]
        with patch.object(runner.observer.sys, "platform", "darwin"), \
             patch.object(runner.observer, "_device_stat", return_value=node), \
             patch.object(runner.observer, "_diskutil_plist", side_effect=[info, apfs]):
            self.assertEqual(adapter(self.song).apfs_role, "Data")

    def test_os_observer_refuses_stale_mount_fallback_and_ambiguous_metadata(self):
        adapter = runner.observer.MacOSVolumeObserver(self.mount)
        node = SimpleNamespace(st_mode=stat.S_IFBLK, st_rdev=self.mount.stat().st_dev)
        for change in (
            {"MountPoint": "/"}, {"MountPoint": None}, {"Mounted": False}, {"Mounted": None}, {"Mounted": 1}, {"FilesystemType": "hfs"},
            {"Internal": None}, {"VolumeUUID": "unknown"},
        ):
            info, apfs = self.os_metadata()
            with self.subTest(change=change), \
                 patch.object(runner.observer.sys, "platform", "darwin"), \
                 patch.object(runner.observer, "_device_stat", return_value=node), \
                 patch.object(runner.observer, "_diskutil_plist", side_effect=[{**info, **change}, apfs]), \
                 self.assertRaises(module.GuardError):
                adapter(self.song)
        for change in (
            {"APFSVolumeUUID": OTHER_UUID}, {"MountPoint": "/"}, {"Roles": None},
            {"Roles": ["Data", "System"]}, {"Mounted": False}, {"Mounted": None},
        ):
            info, apfs = self.os_metadata()
            apfs["Containers"][0]["Volumes"][0].update(change)
            with self.subTest(change=change), \
                 patch.object(runner.observer.sys, "platform", "darwin"), \
                 patch.object(runner.observer, "_device_stat", return_value=node), \
                 patch.object(runner.observer, "_diskutil_plist", side_effect=[info, apfs]), \
                 self.assertRaises(module.GuardError):
                adapter(self.song)
        info, apfs = self.os_metadata()
        wrong_node = SimpleNamespace(st_mode=stat.S_IFBLK, st_rdev=node.st_rdev + 1)
        with patch.object(runner.observer.sys, "platform", "darwin"), \
             patch.object(runner.observer, "_device_stat", return_value=wrong_node), \
             patch.object(runner.observer, "_diskutil_plist", side_effect=[info, apfs]), \
             self.assertRaisesRegex(module.GuardError, "device node"):
            adapter(self.song)
        with patch.object(runner.observer.sys, "platform", "linux"), self.assertRaises(module.GuardError):
            adapter(self.song)

    def test_os_observer_current_native_missing_optional_mount_fields(self):
        adapter = runner.observer.MacOSVolumeObserver(self.mount)
        node = SimpleNamespace(st_mode=stat.S_IFBLK, st_rdev=self.mount.stat().st_dev)
        for omit_volume_mount in (True, False):
            info, apfs = self.os_metadata()
            info.pop("Mounted")
            info["Internal"] = True
            volume = apfs["Containers"][0]["Volumes"][0]
            volume["Roles"] = ["Data"]
            if omit_volume_mount:
                volume.pop("MountPoint")
            else:
                volume["MountPoint"] = None
            with self.subTest(omit_volume_mount=omit_volume_mount), \
                 patch.object(runner.observer.sys, "platform", "darwin"), \
                 patch.object(runner.observer, "_device_stat", return_value=node), \
                 patch.object(runner.observer, "_diskutil_plist", side_effect=[info, apfs]):
                self.assertEqual(adapter(self.song), module.VolumeIdentity(UUID, self.mount, "apfs", "Data", True))

    def test_diskutil_timeout_and_malformed_output_fail_closed_without_retry(self):
        metadata = runner.observer
        result = SimpleNamespace(stdout=plistlib.dumps(self.os_metadata()[0]))
        with patch.object(metadata.subprocess, "run", return_value=result) as command:
            metadata._diskutil_plist(["info", "-plist", str(self.mount)])
        self.assertEqual(command.call_count, 1)
        self.assertEqual(command.call_args.args[0][0], "/usr/sbin/diskutil")
        self.assertEqual(command.call_args.kwargs["timeout"], 10)
        for failure in (
            subprocess.TimeoutExpired("diskutil", 10),
            subprocess.CalledProcessError(1, "diskutil"),
        ):
            with self.subTest(failure=failure), patch.object(metadata.subprocess, "run", side_effect=failure) as command:
                with self.assertRaises(module.GuardError):
                    metadata._diskutil_plist(["info", "-plist", str(self.mount)])
                self.assertEqual(command.call_count, 1)
        with patch.object(metadata.subprocess, "run", return_value=SimpleNamespace(stdout=b"not a plist")):
            with self.assertRaises(module.GuardError):
                metadata._diskutil_plist(["info", "-plist", str(self.mount)])

    def test_production_missing_volume_never_spawns_or_recreates_media(self):
        _path, _raw, config = self.production_config()
        launcher = runner.ReaderLauncher(config)
        self.volume = None
        self.song.unlink()
        self.song.parent.rmdir()
        self.root.rmdir()
        with patch.object(runner.subprocess, "Popen") as spawn, self.assertRaises(module.GuardError):
            self.production_guard(config).run_once(launcher.start, lambda: None)
        spawn.assert_not_called()
        self.assertFalse(self.root.exists())
        self.assertFalse(self.guard().latch_path.exists())

    def test_production_loss_stops_only_owned_child_and_requires_explicit_rearm(self):
        _path, _raw, config = self.production_config()
        unrelated = SyntheticChild()
        guard = self.production_guard(config)
        launcher = runner.ReaderLauncher(config)

        def lose_volume():
            self.volume = None

        with self.production_session() as process:
            with self.assertRaises(module.GuardError):
                runner.run_reader(guard, launcher, lose_volume)
        spawn = process.spawn_mock
        self.assertEqual(spawn.call_count, 1)
        self.assertEqual((process.terminations, process.kills), (1, 1))
        self.assertEqual(unrelated.terminations, 0)
        argv = spawn.call_args.args[0]
        self.assertEqual(argv[:3], [sys.executable, "-I", "-c"])
        sandbox_argv = argv[6:]
        self.assertEqual(sandbox_argv[0], "/usr/bin/sandbox-exec")
        self.assertIn(f"DATA={config.data_dir}", sandbox_argv)
        self.assertIn("deny file-write*", sandbox_argv[4])
        self.assertEqual(argv[-3:], [str(config.binary), "--configfile", str(config.navidrome_config)])
        self.assertTrue(spawn.call_args.kwargs["start_new_session"])
        self.assertTrue(spawn.call_args.kwargs["close_fds"])
        self.assertEqual(spawn.call_args.kwargs["pass_fds"], (int(argv[4]), int(argv[5])))
        self.assertFalse(any(key.startswith("ND_") for key in spawn.call_args.kwargs["env"]))
        self.assertFalse((self.state / runner.UNCLEAN_RUN).exists())
        self.volume = module.VolumeIdentity(UUID, self.mount, "apfs")
        with self.assertRaisesRegex(module.GuardError, "latched"):
            guard.verify()
        with self.assertRaisesRegex(module.GuardError, "second child"):
            launcher.start()
        guard.rearm_manually(lambda: True)
        guard.verify()
        self.assertEqual(spawn.call_count, 1)  # rearm does not launch or restart

    def test_running_e1_publication_drift_latches_and_stops_owned_process(self):
        _path, _raw, config = self.production_config()
        launcher = runner.ReaderLauncher(config)
        guard = self.production_guard(config)

        def invalidate_publication():
            self.publish_witness(epoch=config.contract.epoch, publication_state="E1-incomplete", media_root=str(self.root))

        with self.production_session() as process, \
             self.assertRaisesRegex(module.GuardError, "published E1"):
            runner.run_reader(guard, launcher, invalidate_publication)
        self.assertEqual(process.terminations, 1)
        self.assertTrue(guard.latch_path.is_file())
        self.assertEqual(process.spawn_mock.call_count, 1)

    def test_reviewed_binary_hash_mismatch_never_executes_a_child(self):
        _path, _raw, config = self.production_config()
        config.binary.write_bytes(b"not the reviewed binary")
        launcher = runner.ReaderLauncher(config)
        with patch.object(runner.os, "access", return_value=True), \
             patch.object(runner.subprocess, "Popen") as spawn, \
             self.assertRaisesRegex(module.GuardError, "reader start failed"):
            self.production_guard(config).run_once(launcher.start, lambda: None)
        spawn.assert_not_called()
        self.assertTrue(self.guard().latch_path.exists())

    def test_owned_session_escalates_before_reaping_and_checks_group_absence(self):
        _path, _raw, config = self.production_config()
        launcher = runner.ReaderLauncher(config)
        with self.production_session() as process:
            child = launcher.start()
            module.ReaderGuard._stop(child)
            launcher.finish()
            launcher.close()
        self.assertEqual((process.terminations, process.kills), (1, 1))
        self.assertEqual(process.events, [
            "spawn", ("signal", runner.signal.SIGTERM),
            ("signal", runner.signal.SIGKILL), "reap", ("signal", 0),
        ])
        self.assertTrue(child.quiescent)
        self.assertFalse((self.state / runner.UNCLEAN_RUN).exists())
        with self.assertRaisesRegex(module.GuardError, "released reader group"):
            child._signal_group(runner.signal.SIGKILL)

    def test_supervisor_signal_during_spawn_retains_handle_and_stops_child(self):
        _path, _raw, config = self.production_config()
        launcher = runner.ReaderLauncher(config)
        handlers = {}
        process = SyntheticSession()

        def save_handler(number, handler):
            handlers[number] = handler

        process.on_spawn = lambda: handlers[runner.signal.SIGTERM](runner.signal.SIGTERM, None)
        with self.production_session(process), \
             patch.object(runner.signal, "getsignal", return_value=runner.signal.SIG_DFL), \
             patch.object(runner.signal, "signal", side_effect=save_handler), \
             self.assertRaises(module.GuardError):
            runner.run_reader(self.production_guard(config), launcher, lambda: None)
        self.assertEqual(process.terminations, 1)
        self.assertTrue(self.guard().latch_path.is_file())
        self.assertFalse((self.state / runner.UNCLEAN_RUN).exists())

    def test_unclean_supervisor_death_blocks_run_verify_and_rearm_with_free_flock(self):
        path, _raw, config = self.production_config()
        launcher = runner.ReaderLauncher(config)
        with self.production_session() as process:
            with runner.reader_lease(self.state):
                launcher.start()
                marker = self.state / runner.UNCLEAN_RUN
                self.assertEqual(json.loads(marker.read_text())["state"], "quiescence-unconfirmed")
                # Model SIGKILL: Python finally/finish never ran. FDs/flock can
                # close while the previously owned reader/helper is still alive.
                launcher.close()
            self.assertIsNone(process.reader.poll())
            for operation in ("run", "verify", "rearm"):
                argv = ["run-guarded.py", operation, "--config", str(path)]
                if operation == "rearm":
                    argv += ["--confirm-epoch", config.contract.epoch]
                with self.subTest(operation=operation), \
                     patch.object(runner.sys, "argv", argv), \
                     patch.object(runner.PublishedE1Guard, "rearm_manually") as rearm, \
                     patch.object(runner.observer, "_diskutil_plist") as observe:
                    self.assertEqual(runner.main(), 2)
                    rearm.assert_not_called()
                    observe.assert_not_called()
                    self.assertTrue(marker.is_file())
            self.assertEqual(process.spawn_mock.call_count, 1)
            self.assertIsNone(process.reader.poll())
        # An old timestamp/dead-looking PID (or garbage) must never expire or
        # turn a newly acquired flock into cleanup proof. Nothing adopts/signals
        # these stored identities; this interlock has no automatic recovery API.
        for stale in ('{"pid": 99999999, "expires_at": 0}', "malformed"):
            marker.write_text(stale)
            with self.subTest(stale=stale), self.assertRaisesRegex(module.GuardError, "unclean reader"):
                with runner.reader_lease(self.state):
                    self.fail("stale unclean-run record was cleared automatically")
        self.assertEqual(process.events, ["spawn"])

    def test_interlock_file_and_directory_are_synced_before_spawn(self):
        _path, _raw, config = self.production_config()
        self.admit_fixture_restore(config)
        launcher = runner.ReaderLauncher(config)
        events = []
        original_fsync = os.fsync

        def fsync(fd):
            events.append("directory" if stat.S_ISDIR(os.fstat(fd).st_mode) else "file")
            original_fsync(fd)

        process = SyntheticSession()
        process.on_spawn = lambda: self.assertEqual(events, ["file", "directory"])
        with self.production_session(process), patch.object(runner.os, "fsync", side_effect=fsync):
            launcher.start()
            launcher.finish()
            launcher.close()
        self.assertFalse((self.state / runner.UNCLEAN_RUN).exists())

    def test_interlock_sync_failure_never_spawns_and_remains_blocked(self):
        _path, _raw, config = self.production_config()
        self.admit_fixture_restore(config)
        launcher = runner.ReaderLauncher(config)
        with patch.object(runner.os, "access", return_value=True), \
             patch.object(runner.subprocess, "run", return_value=SimpleNamespace(
                 returncode=0, stdout=b"fixture-native-version\n", stderr=b"")), \
             patch.object(runner, "_sync_directory", side_effect=OSError("synthetic sync failure")), \
             patch.object(runner.subprocess, "Popen") as spawn, \
             self.assertRaises(module.GuardError):
            runner.run_reader(self.production_guard(config), launcher, lambda: None)
        spawn.assert_not_called()
        self.assertTrue((self.state / runner.UNCLEAN_RUN).is_file())
        with self.assertRaisesRegex(module.GuardError, "unclean reader"):
            with runner.reader_lease(self.state):
                self.fail("failed durability was treated as cleanup")

    def test_primary_exit_still_kills_owned_helper_before_clearing_interlock(self):
        _path, _raw, config = self.production_config()
        helper = SyntheticChild()
        unrelated = SyntheticChild()
        process = SyntheticSession([helper])
        launcher = runner.ReaderLauncher(config)
        with self.production_session(process):
            self.assertEqual(runner.run_reader(self.production_guard(config), launcher,
                                              lambda: process.report(0)), 0)
        self.assertEqual(process.reader.poll(), 0)
        self.assertEqual(helper.poll(), -9)  # survived the primary and TERM
        self.assertIsNone(unrelated.poll())
        self.assertTrue(launcher.child.quiescent)
        self.assertFalse((self.state / runner.UNCLEAN_RUN).exists())
        self.assertLess(process.events.index(("signal", runner.signal.SIGKILL)),
                        process.events.index("reap"))
        self.assertEqual(process.events[-1], ("signal", 0))
        with runner.reader_lease(self.state):
            pass  # confirmed whole-group cleanup, not primary exit, frees it

    @unittest.skipUnless(sys.platform == "darwin", "native MBA reader cleanup targets macOS")
    def test_native_synthetic_anchor_cleans_helper_after_primary_exit(self):
        # Exercise the exact anchor code with disposable Python stand-ins, never
        # Navidrome, diskutil, sandbox-exec, a real mount or a process-name kill.
        self.state.chmod(0o700)
        interlock = runner.RunInterlock(self.contract)
        interlock.arm()
        ready = self.base / "synthetic-helper-ready"
        helper_code = (
            "import pathlib,signal,sys,time; "
            "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
            "pathlib.Path(sys.argv[1]).write_text('ready'); time.sleep(30)"
        )
        reader_code = """
import pathlib, subprocess, sys, time
subprocess.Popen([sys.executable, '-I', '-c', sys.argv[2], sys.argv[1]])
deadline = time.monotonic() + 5
while not pathlib.Path(sys.argv[1]).is_file() and time.monotonic() < deadline:
    time.sleep(0.01)
raise SystemExit(0 if pathlib.Path(sys.argv[1]).is_file() else 3)
"""
        status_read, status_write = os.pipe()
        control_read, control_write = os.pipe()
        os.set_blocking(status_read, False)
        try:
            process = subprocess.Popen(
                [sys.executable, "-I", "-c", runner.SESSION_ANCHOR,
                 str(status_write), str(control_read), sys.executable, "-I", "-c",
                 reader_code, str(ready), helper_code],
                stdin=subprocess.DEVNULL, close_fds=True, start_new_session=True,
                pass_fds=(status_write, control_read),
            )
        except BaseException:
            os.close(status_read)
            os.close(control_write)
            interlock.close()
            raise
        finally:
            os.close(status_write)
            os.close(control_read)
        child = runner.OwnedChild(process, status_read, control_write)
        try:
            deadline = runner.time.monotonic() + 10
            while (status := child.poll()) is None and runner.time.monotonic() < deadline:
                runner.time.sleep(0.01)
            self.assertEqual(status, 0)
            self.assertTrue(ready.is_file())
            self.assertIsNone(process.returncode)  # anchor has never been reaped
            self.assertTrue(interlock.path.is_file())
            child.shutdown()
            self.assertTrue(child.quiescent)
            interlock.clear_after_quiescence(child)
            self.assertFalse(interlock.path.exists())
        finally:
            try:
                child.shutdown()
            finally:
                child.close_channels()
                interlock.close()

    def test_surviving_helper_keeps_interlock_and_never_signals_reused_group(self):
        _path, _raw, config = self.production_config()
        helper = SyntheticChild()
        process = SyntheticSession([helper], helpers_survive_kill=True)
        launcher = runner.ReaderLauncher(config)
        with self.production_session(process), \
             self.assertRaisesRegex(module.GuardError, "cleanup unconfirmed"):
            runner.run_reader(self.production_guard(config), launcher, lambda: process.report(0))
        self.assertTrue(process.reaped)
        self.assertIsNone(helper.poll())
        self.assertFalse(launcher.child.quiescent)
        self.assertTrue((self.state / runner.UNCLEAN_RUN).is_file())
        reap = process.events.index("reap")
        self.assertTrue(process.events[reap + 1:])
        self.assertTrue(all(event == ("signal", 0) for event in process.events[reap + 1:]))
        with self.assertRaisesRegex(module.GuardError, "unclean reader"):
            with runner.reader_lease(self.state):
                self.fail("surviving helper released reader capacity")

    def test_dead_anchor_is_not_reaped_until_group_cleanup_has_been_signalled(self):
        _path, _raw, config = self.production_config()
        helper = SyntheticChild()
        process = SyntheticSession([helper])
        launcher = runner.ReaderLauncher(config)

        def lose_anchor():
            process.returncode = -9
            process.close_status()  # primary/helper can outlive a killed anchor

        with self.production_session(process), self.assertRaises(module.GuardError):
            runner.run_reader(self.production_guard(config), launcher, lose_anchor)
        self.assertEqual(helper.poll(), -9)
        self.assertTrue(launcher.child.quiescent)
        self.assertTrue(self.guard().latch_path.is_file())
        self.assertFalse((self.state / runner.UNCLEAN_RUN).exists())
        self.assertLess(process.events.index(("signal", runner.signal.SIGKILL)),
                        process.events.index("reap"))

    def test_nondefault_sigchld_policy_is_refused_before_spawn(self):
        _path, _raw, config = self.production_config()
        launcher = runner.ReaderLauncher(config)
        with patch.object(runner.signal, "getsignal", return_value=runner.signal.SIG_IGN), \
             patch.object(runner.os, "access", return_value=True), \
             patch.object(runner.subprocess, "Popen") as spawn, \
             self.assertRaisesRegex(module.GuardError, "non-reaping SIGCHLD"):
            launcher.start()
        spawn.assert_not_called()
        self.assertFalse((self.state / runner.UNCLEAN_RUN).exists())

    def test_reader_lease_prohibits_a_second_reader_or_rearm(self):
        self.state.chmod(0o700)
        with runner.reader_lease(self.state):
            with self.assertRaisesRegex(module.GuardError, "holds the lease"):
                with runner.reader_lease(self.state):
                    self.fail("a second supervisor acquired the same lease")

    def test_successful_child_exit_does_not_auto_restart(self):
        children = []

        def start():
            child = SyntheticChild()
            children.append(child)
            return child

        def finish():
            children[0].exit_code = 0

        self.assertEqual(self.guard().run_once(start, finish), 0)
        self.assertEqual(len(children), 1)
        self.assertFalse(self.guard().latch_path.exists())


if __name__ == "__main__":
    unittest.main()
