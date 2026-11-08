"""Disposable-only tests: uv run python -I checks/mba-media-stage-test.py."""
from __future__ import annotations

import copy
import fcntl
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
import socket
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

REPO = Path(__file__).parents[1]
STAGE = REPO / "rig/bootstrap/mba-media-stage.py"
CENSUS = REPO / "checks/mba-media-census.py"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


stage = load(STAGE, "stage_fixture_module")
census = load(CENSUS, "census_fixture_module")


class StageFixtures(unittest.TestCase):
    def setUp(self):
        # /var and /tmp can be symlink aliases on macOS; pinned roots must be literal.
        self.temp = tempfile.TemporaryDirectory(dir="/private/tmp" if Path("/private/tmp").is_dir() else None)
        self.addCleanup(self.temp.cleanup)
        base = Path(os.path.realpath(self.temp.name))
        self.base = base
        self.source = base / "source"
        self.dest = base / "destination"
        (self.source / "MP3" / "Album").mkdir(parents=True)
        (self.dest / "UNserved" / ".journal").mkdir(parents=True)
        (self.dest / "UNserved" / "MP3" / "Album").mkdir(parents=True)
        self.relative = "MP3/Album/track.mp3"
        (self.source / self.relative).write_bytes(b"fixture media bytes\x00" * 17)
        self.envelope = census.collect(self.source, "source", "E0")

    def stage(self, **kwargs):
        return stage.stage_fixture(self.source, self.dest, self.envelope, self.relative,
                                   fixture_root=self.base, low_water=0, **kwargs)

    def journal(self):
        return self.dest / "UNserved" / ".journal" / (hashlib.sha256(self.relative.encode()).hexdigest() + ".json")

    def temp_path(self):
        return self.dest / "UNserved" / "MP3" / "Album" / (".stage-" + hashlib.sha256(self.relative.encode()).hexdigest())

    def test_plan_cli_is_read_only_and_never_publishes_e0(self):
        census_json = Path(self.temp.name) / "census.json"
        census_json.write_text(json.dumps(self.envelope), encoding="utf-8")
        before = sorted(str(p.relative_to(self.dest)) for p in self.dest.rglob("*"))
        output = subprocess.run(["uv", "run", "python", "-I", str(STAGE), "--census", str(census_json)],
                                capture_output=True, text=True, check=True, env={**os.environ, "UV_OFFLINE": "1"})
        report = json.loads(output.stdout)
        self.assertEqual(report["operation"], "offline_plan_only")
        self.assertEqual(report["epoch"], "E0")
        self.assertEqual(report["publication"], "forbidden")
        self.assertEqual(report["file_count"], 1)
        self.assertEqual(report["unresolved_count"], 0)
        self.assertNotIn(self.relative, output.stdout)
        self.assertNotIn('"path"', output.stdout)
        self.assertEqual(before, sorted(str(p.relative_to(self.dest)) for p in self.dest.rglob("*")))
        explicit = subprocess.run(["uv", "run", "python", "-I", str(STAGE), "--census", str(census_json), "--dry-run"],
                                  capture_output=True, text=True, check=True, env={**os.environ, "UV_OFFLINE": "1"})
        self.assertEqual(json.loads(explicit.stdout), report)
        self.assertFalse((self.dest / "MP3").exists())
        refused = subprocess.run(["uv", "run", "python", "-I", str(STAGE), "--census", str(census_json), "--apply"],
                                 capture_output=True, text=True, env={**os.environ, "UV_OFFLINE": "1"})
        self.assertNotEqual(refused.returncode, 0)

    def test_census_depth_first_order_is_accepted(self):
        # Sibling punctuation can sort before a descendant even though G2
        # walks each sorted directory recursively before visiting that sibling.
        (self.source / "MP3.a").write_bytes(b"unresolved sibling")
        census_envelope = census.collect(self.source, "source", "E0")
        self.assertNotEqual([row["path"] for row in census_envelope["manifest"]["items"]],
                            sorted(row["path"] for row in census_envelope["manifest"]["items"]))
        self.assertEqual(stage.plan(census_envelope)["status"], "provisional")
        self.assertEqual(stage.plan(census_envelope)["retained_companion_count"], 1)

    def test_stage_and_recovery_verified_in_unserved_only(self):
        self.assertEqual(self.stage(), "complete")
        self.assertEqual((self.dest / "UNserved" / self.relative).read_bytes(),
                         (self.source / self.relative).read_bytes())
        self.assertFalse((self.dest / self.relative).exists())
        self.assertEqual(stage.recover_fixture(self.source, self.dest, self.envelope, self.relative, fixture_root=self.base), "complete")
        with self.assertRaises(stage.StageError):
            self.stage()

    def test_destination_pin_rejects_mixed_epoch_and_manifest(self):
        self.assertEqual(self.stage(), "complete")
        pin = self.dest / "UNserved" / ".journal" / ".cohort.json"
        frozen = pin.read_bytes()
        other = "MP3/Album/second.mp3"
        (self.source / other).write_bytes(b"another fixture")
        for epoch in ("E1", "E0"):
            with self.subTest(epoch=epoch):
                newer = census.collect(self.source, "source", epoch)
                with self.assertRaises(stage.StageError):
                    stage.stage_fixture(self.source, self.dest, newer, other,
                                        fixture_root=self.base, low_water=0)
                self.assertFalse((self.dest / "UNserved" / other).exists())
                self.assertEqual(pin.read_bytes(), frozen)
        with self.assertRaises(stage.StageError):
            stage.recover_fixture(self.source, self.dest, newer, self.relative, fixture_root=self.base)

    def test_recovery_does_not_post_after_verified_path_swap(self):
        def interrupt(point):
            if point == "after_rename":
                raise InterruptedError(point)
        with self.assertRaises(InterruptedError):
            self.stage(fault=interrupt)
        final = self.dest / "UNserved" / self.relative
        original_check = stage._check_existing
        def swap_after_check(*args):
            checked = original_check(*args)
            final.unlink()
            final.write_bytes(b"swapped after verification")
            return checked
        with patch.object(stage, "_check_existing", side_effect=swap_after_check):
            with self.assertRaises(stage.StageError):
                stage.recover_fixture(self.source, self.dest, self.envelope,
                                      self.relative, fixture_root=self.base)
        self.assertEqual(json.loads(self.journal().read_text())["phase"], "pre")

    def test_destination_open_failure_closes_source_fd(self):
        held = self.base / "destination-held"
        self.dest.rename(held)
        self.dest.symlink_to(held, target_is_directory=True)
        real_root = stage._root
        for action in (lambda: self.stage(),
                       lambda: stage.recover_fixture(self.source, self.dest, self.envelope,
                                                     self.relative, fixture_root=self.base)):
            opened_source = []
            def spy(path, opened_source=opened_source):
                fd = real_root(path)
                if path == self.source:
                    opened_source.append(fd)
                return fd
            with self.subTest(action=action), patch.object(stage, "_root", side_effect=spy):
                with self.assertRaises(OSError):
                    action()
                self.assertEqual(len(opened_source), 1)
                with self.assertRaises(OSError):
                    os.fstat(opened_source[0])

    def test_faults_leave_durable_pre_and_recovery_fails_closed(self):
        for point in ("after_pre", "during_write", "before_fsync", "after_fsync", "before_rename"):
            with self.subTest(point=point):
                self.setUp()
                def interrupt(current, point=point):
                    if current == point:
                        raise InterruptedError(point)
                with self.assertRaises(InterruptedError):
                    self.stage(fault=interrupt)
                self.assertTrue(self.journal().exists())
                self.assertEqual(json.loads(self.journal().read_text())["phase"], "pre")
                self.assertFalse((self.dest / "UNserved" / self.relative).exists())
                with self.assertRaises(stage.StageError):
                    stage.recover_fixture(self.source, self.dest, self.envelope, self.relative, fixture_root=self.base)

    def test_rename_interruption_keeps_pre_even_with_verified_final(self):
        def interrupt(point):
            if point == "after_rename":
                raise InterruptedError(point)
        with self.assertRaises(InterruptedError):
            self.stage(fault=interrupt)
        self.assertEqual(json.loads(self.journal().read_text())["phase"], "pre")
        with self.assertRaises(stage.StageError):
            stage.recover_fixture(self.source, self.dest, self.envelope, self.relative, fixture_root=self.base)
        self.assertEqual(json.loads(self.journal().read_text())["phase"], "pre")
        self.assertFalse(self.temp_path().exists())

    def test_recovery_rejects_changed_source_or_final(self):
        def interrupt(point):
            if point == "after_rename":
                raise InterruptedError(point)
        with self.assertRaises(InterruptedError):
            self.stage(fault=interrupt)
        final = self.dest / "UNserved" / self.relative
        original = final.read_bytes()
        final.write_bytes(b"tampered")
        with self.assertRaises(stage.StageError):
            stage.recover_fixture(self.source, self.dest, self.envelope, self.relative, fixture_root=self.base)
        final.write_bytes(original)
        (self.source / self.relative).write_bytes(b"changed")
        with self.assertRaises(stage.StageError):
            stage.recover_fixture(self.source, self.dest, self.envelope, self.relative, fixture_root=self.base)
        self.assertEqual(json.loads(self.journal().read_text())["phase"], "pre")

    def test_swapped_temp_and_final_cannot_get_post_journal(self):
        def swap_temp(point):
            if point == "before_rename":
                self.temp_path().unlink()
                self.temp_path().symlink_to(self.source / self.relative)
        with self.assertRaises(stage.StageError):
            self.stage(fault=swap_temp)
        self.assertEqual(json.loads(self.journal().read_text())["phase"], "pre")
        self.assertFalse((self.dest / "UNserved" / self.relative).exists())
        self.setUp()
        def swap_final(point):
            if point == "after_rename":
                final = self.dest / "UNserved" / self.relative
                final.unlink()
                final.write_bytes(b"replacement")
        with self.assertRaises(stage.StageError):
            self.stage(fault=swap_final)
        self.assertEqual(json.loads(self.journal().read_text())["phase"], "pre")

    def test_fixture_boundary_rejects_nonprivate_or_unrelated_root(self):
        with self.assertRaises(stage.StageError):
            stage.stage_fixture(self.source, self.dest, self.envelope, self.relative,
                                fixture_root=self.source, low_water=0)
        self.base.chmod(0o755)
        with self.assertRaises(stage.StageError):
            self.stage()
        self.base.chmod(0o700)

    def test_changed_source_and_hardlink_are_rejected(self):
        (self.source / self.relative).write_bytes(b"changed bytes")
        with self.assertRaises(stage.StageError):
            self.stage()
        self.assertFalse((self.dest / "UNserved" / self.relative).exists())
        self.setUp()
        os.link(self.source / self.relative, self.source / "extra-link")
        with self.assertRaises(stage.StageError):
            self.stage()

    def test_destination_collision_and_symlink_escapes(self):
        final = self.dest / "UNserved" / self.relative
        final.write_bytes(b"previous data")
        with self.assertRaises(stage.StageError):
            self.stage()
        self.assertEqual(final.read_bytes(), b"previous data")
        final.unlink()
        (self.dest / "UNserved" / "MP3" / "Album").rmdir()
        (self.dest / "UNserved" / "MP3" / "Album").symlink_to(self.source / "MP3" / "Album")
        with self.assertRaises((OSError, stage.StageError)):
            self.stage()
        self.assertEqual((self.source / self.relative).read_bytes(), b"fixture media bytes\x00" * 17)

    def test_source_symlink_replacement_rejected(self):
        original = self.source / self.relative
        original.unlink()
        original.symlink_to(self.dest / "UNserved" / "MP3" / "Album" / "outside")
        with self.assertRaises((OSError, stage.StageError)):
            self.stage()

    def test_root_identity_and_low_water_rejected(self):
        wrong = copy.deepcopy(self.envelope)
        wrong["receipt"]["root_inode"] += 1
        with self.assertRaises(stage.StageError):
            stage.stage_fixture(self.source, self.dest, wrong, self.relative, fixture_root=self.base, low_water=0)
        with self.assertRaises(stage.StageError):
            stage.stage_fixture(self.source, self.dest, self.envelope, self.relative, fixture_root=self.base, low_water=2**63)
        self.assertFalse(self.journal().exists())

    def test_invalid_manifest_receipt_unknown_cloud_and_ancestry(self):
        variations = []
        bad = copy.deepcopy(self.envelope); bad["receipt"]["status"] = "open"; variations.append(bad)
        bad = copy.deepcopy(self.envelope); bad["receipt"]["manifest_sha256"] = "0" * 64; variations.append(bad)
        bad = copy.deepcopy(self.envelope); bad["receipt"]["rows"] -= 1; variations.append(bad)
        bad = copy.deepcopy(self.envelope); bad["manifest"]["items"][-1]["local"] = False
        bad["receipt"]["manifest_sha256"] = stage._digest(bad["manifest"]); variations.append(bad)
        bad = copy.deepcopy(self.envelope); bad["manifest"]["items"][-1]["sha256"] = "0" * 64
        bad["receipt"]["manifest_sha256"] = stage._digest(bad["manifest"]); variations.append(bad)
        bad = copy.deepcopy(self.envelope); bad["manifest"]["items"][-1]["path"] = "MP3/../track.mp3"
        bad["receipt"]["manifest_sha256"] = stage._digest(bad["manifest"]); variations.append(bad)
        bad = copy.deepcopy(self.envelope); bad["manifest"]["items"] = bad["manifest"]["items"][1:]
        bad["receipt"]["rows"] -= 1
        bad["receipt"]["manifest_sha256"] = stage._digest(bad["manifest"]); variations.append(bad)
        for invalid in variations:
            with self.subTest(invalid=invalid):
                with self.assertRaises((ValueError, TypeError)):
                    stage.plan(invalid) if invalid["manifest"]["items"][-1].get("sha256") != "0" * 64 else stage.stage_fixture(
                        self.source, self.dest, invalid, self.relative, fixture_root=self.base, low_water=0)
        self.assertFalse((self.dest / "UNserved" / self.relative).exists())

    def test_one_inflight_file_lock(self):
        journal = self.dest / "UNserved" / ".journal"
        lock = os.open(journal / ".stage.lock", os.O_CREAT | os.O_RDWR, 0o600)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(stage.StageError):
                self.stage()
        finally:
            os.close(lock)
        self.assertFalse(self.journal().exists())


class ProductionFixtures(unittest.TestCase):
    """Exercise the production writer and actual read-only source subprocess.

    Only the SSH transport and macOS volume observation edge are substituted;
    both sides use real files, durable journals, hashes and exclusive renames.
    """

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir="/private/tmp" if Path("/private/tmp").is_dir() else None)
        self.addCleanup(self.temp.cleanup)
        self.base = Path(os.path.realpath(self.temp.name))
        self.source = self.base / "source"
        self.target = self.base / "target"
        (self.source / "MP3" / "Album").mkdir(parents=True)
        self.target.mkdir(mode=0o700)
        self.relative = "MP3/Album/track.mp3"
        (self.source / self.relative).write_bytes(b"production fixture audio\x00" * 91)
        self.envelope = census.collect(self.source, "source", "E0")
        self.census_path = self.base / "source-census.json"
        self.census_path.write_text(json.dumps(self.envelope))
        self.census_path.chmod(0o600)
        key = self.base / "fixture-key"
        hosts = self.base / "fixture-known-hosts"
        key.write_text("disposable metadata-only fixture; not an SSH key")
        key.chmod(0o600)
        hosts.write_text("disposable host-key fixture")
        hosts.chmod(0o600)
        space = os.statvfs(self.target)
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        self.contract = {
            "schema_version": 1, "campaign_id": "E0-disposable", "epoch": "E0",
            "manifest_sha256": self.envelope["receipt"]["manifest_sha256"], "started_at": now,
            "capacity_receipt_sha256": "a" * 64,
            "source": {"hostname": socket.gethostname(), "root": str(self.source),
                "device": self.source.stat().st_dev, "inode": self.source.stat().st_ino,
                "ssh_host": "mbp-fixture", "ssh_user": "fixture", "ssh_port": 22,
                "identity_file": str(key), "identity_device": key.stat().st_dev,
                "identity_inode": key.stat().st_ino, "known_hosts_file": str(hosts),
                "known_hosts_sha256": hashlib.sha256(hosts.read_bytes()).hexdigest(),
                "python": sys.executable, "script": str(STAGE),
                "script_sha256": hashlib.sha256(STAGE.read_bytes()).hexdigest(),
                "census": str(self.census_path)},
            "target": {"hostname": "mba-disposable-fixture", "root": str(self.target),
                "device": self.target.stat().st_dev, "inode": self.target.stat().st_ino,
                "mountpoint": str(self.base), "volume_uuid": "fixture-volume",
                "filesystem_capacity_bytes": space.f_blocks * space.f_frsize,
                "low_water_bytes": 1, "reserved_bytes": 1,
                "observed_free_bytes": space.f_bavail * space.f_frsize, "observed_at": now},
        }
        self.calls = []
        self.observer = patch.object(stage, "_observe_target", side_effect=self.observe)
        self.transport = patch.object(stage, "_source_process", side_effect=self.local_source)
        self.observer.start()
        self.transport.start()
        self.addCleanup(self.observer.stop)
        self.addCleanup(self.transport.stop)

    def observe(self, target, fd):
        self.assertEqual((os.fstat(fd).st_dev, os.fstat(fd).st_ino), (target["device"], target["inode"]))
        self.assertEqual((self.target.stat().st_dev, self.target.stat().st_ino), (target["device"], target["inode"]))

    @contextmanager
    def local_source(self, contract, relative):
        self.calls.append(relative)
        process = subprocess.Popen([sys.executable, "-I", str(STAGE), "--source-stream"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            process.stdin.write(json.dumps(stage._source_request(contract, relative)).encode())
            process.stdin.close()
            yield process
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()
            process.stderr.close()

    def run_stage(self, **kwargs):
        return stage.stage_e0(self.contract, self.envelope, **kwargs)

    @property
    def final(self):
        return self.target / "UNserved" / self.relative

    @property
    def journal(self):
        return self.target / ".journal"

    def test_actual_source_stream_serial_copy_final_readback_and_idempotence(self):
        source_before = (self.source / self.relative).read_bytes()
        result = self.run_stage()
        self.assertEqual(result["status"], "E0_UNSERVED_VERIFIED")
        self.assertEqual(result["publication"], "forbidden")
        self.assertFalse(result["backup_or_E1_publication_proven"])
        self.assertEqual(self.final.read_bytes(), source_before)
        self.assertEqual(self.calls, [self.relative, None])
        self.assertFalse((self.target / "MP3").exists())
        original_inode = self.final.stat().st_ino
        self.calls.clear()
        again = self.run_stage()
        self.assertEqual(again["copied_this_run"], 0)
        self.assertEqual(again["verified_reused_this_run"], 1)
        self.assertEqual(self.final.stat().st_ino, original_inode)
        self.assertEqual(self.calls, [None])
        self.assertEqual((self.source / self.relative).read_bytes(), source_before)

    def test_partial_is_retained_then_resume_allocates_one_new_temp(self):
        def stop(point):
            if point == "during_write":
                raise InterruptedError("fixture interruption")
        with self.assertRaises(InterruptedError):
            self.run_stage(fault=stop)
        self.assertFalse(self.final.exists())
        partials = list(self.final.parent.glob(".stage-*"))
        self.assertEqual(len(partials), 1)
        retained_bytes = partials[0].read_bytes()
        result = self.run_stage()
        self.assertEqual(result["copied_this_run"], 1)
        retained = list(self.journal.glob(".retained-*"))
        self.assertEqual(len(retained), 1)
        self.assertEqual(retained[0].read_bytes(), retained_bytes)
        self.assertEqual(list(self.final.parent.glob(".stage-*")), [])
        self.assertTrue(list(self.journal.glob("*.attempt-1")))

    def test_post_rename_resume_verifies_existing_good_file_without_overwrite(self):
        def stop(point):
            if point == "after_rename":
                raise InterruptedError("fixture interruption")
        with self.assertRaises(InterruptedError):
            self.run_stage(fault=stop)
        inode = self.final.stat().st_ino
        self.calls.clear()
        result = self.run_stage()
        self.assertEqual(result["verified_reused_this_run"], 1)
        self.assertEqual(self.final.stat().st_ino, inode)
        self.assertEqual(self.calls, [None])

    def test_tampered_or_missing_completed_file_is_not_replayed(self):
        self.run_stage()
        self.final.write_bytes(b"changed final")
        self.calls.clear()
        with self.assertRaises(stage.StageError):
            self.run_stage()
        self.assertEqual(self.final.read_bytes(), b"changed final")
        self.assertEqual(self.calls, [])
        self.final.unlink()
        with self.assertRaises(stage.StageError):
            self.run_stage()
        self.assertEqual(self.calls, [])

    def test_source_drift_fails_closed_with_retained_partial_and_no_result(self):
        (self.source / self.relative).write_bytes(b"changed source")
        with self.assertRaises(stage.StageError):
            self.run_stage()
        self.assertFalse(self.final.exists())
        self.assertFalse((self.journal / ".result.json").exists())
        self.assertTrue(list(self.final.parent.glob(".stage-*")))

    def test_final_full_source_verification_detects_late_source_change(self):
        original = (self.source / self.relative).read_bytes()
        def change(point):
            if point == "after_rename":
                (self.source / self.relative).write_bytes(b"changed after file stream")
        with self.assertRaises(stage.StageError):
            self.run_stage(fault=change)
        self.assertEqual(self.final.read_bytes(), original)
        self.assertFalse((self.journal / ".result.json").exists())

    def test_contract_campaign_epoch_and_capacity_pins_are_enforced(self):
        self.run_stage()
        before = self.final.read_bytes()
        for field, value in (("campaign_id", "different"), ("capacity_receipt_sha256", "b" * 64), ("epoch", "E1")):
            changed = copy.deepcopy(self.contract)
            changed[field] = value
            with self.subTest(field=field), self.assertRaises(stage.StageError):
                stage.stage_e0(changed, self.envelope)
        self.assertEqual(self.final.read_bytes(), before)

    def test_nonempty_new_root_and_unrecorded_collision_are_preserved(self):
        marker = self.target / "unrelated"
        marker.write_bytes(b"keep")
        with self.assertRaises(stage.StageError):
            self.run_stage()
        self.assertEqual(marker.read_bytes(), b"keep")
        self.assertFalse((self.target / "UNserved").exists())
        marker.unlink()
        def stop(point):
            if point == "after_pre":
                raise InterruptedError("fixture interruption")
        with self.assertRaises(InterruptedError):
            self.run_stage(fault=stop)
        self.final.write_bytes(b"foreign final")
        with self.assertRaises(stage.StageError):
            self.run_stage()
        self.assertEqual(self.final.read_bytes(), b"foreign final")

    def test_live_low_water_stops_before_source_stream(self):
        self.contract["target"]["reserved_bytes"] = os.statvfs(self.target).f_bavail * os.statvfs(self.target).f_frsize
        with self.assertRaises(stage.StageError):
            self.run_stage()
        self.assertEqual(self.calls, [])
        self.assertFalse((self.journal / ".production.json").exists())

    def test_symlink_target_and_census_pin_refuse(self):
        held = self.base / "held-target"
        self.target.rename(held)
        self.target.symlink_to(held, target_is_directory=True)
        with self.assertRaises(OSError):
            self.run_stage()
        self.target.unlink()
        held.rename(self.target)
        self.contract["manifest_sha256"] = "0" * 64
        with self.assertRaises(stage.StageError):
            self.run_stage()
        self.assertEqual(list(self.target.iterdir()), [])

    def test_strict_ssh_argv_uses_only_metadata_pinned_key_and_hosts(self):
        argv = stage._ssh_argv(self.contract["source"])
        self.assertEqual(argv[:4], ["/usr/bin/ssh", "-F", "/dev/null", "-T"])
        for value in ("BatchMode=yes", "StrictHostKeyChecking=yes", "IdentityAgent=none", "IdentitiesOnly=yes", "PasswordAuthentication=no"):
            self.assertIn(value, argv)
        self.assertIn("fixture@mbp-fixture", argv)
        Path(self.contract["source"]["known_hosts_file"]).write_text("changed pins")
        with self.assertRaises(stage.StageError):
            stage._ssh_argv(self.contract["source"])

    def test_private_input_requires_mode_and_rejects_duplicate_fields(self):
        path = self.base / "contract.json"
        path.write_text('{"same":1,"same":2}')
        path.chmod(0o600)
        with self.assertRaises(stage.StageError):
            stage.private_json(path, 65536)
        path.write_text('{}')
        path.chmod(0o644)
        with self.assertRaises(stage.StageError):
            stage.private_json(path, 65536)

    def test_directory_swap_before_promotion_retains_partial_and_refuses_completion(self):
        held = self.base / "held-album"
        def swap(point):
            if point == "before_rename":
                self.final.parent.rename(held)
                self.final.parent.mkdir(mode=0o700)
        with self.assertRaises(stage.StageError):
            self.run_stage(fault=swap)
        self.assertFalse(self.final.exists())
        self.assertTrue(list(held.glob(".stage-*")))
        self.assertEqual(json.loads((self.journal / ".run.json").read_text())["status"], "INCOMPLETE")
        self.assertFalse((self.journal / ".result.json").exists())

    def test_failed_reverification_never_reuses_old_completion_as_current(self):
        self.run_stage()
        original = json.loads((self.journal / ".result.json").read_text())
        (self.source / self.relative).write_bytes(b"later source epoch")
        with self.assertRaises(stage.StageError):
            self.run_stage()
        run = json.loads((self.journal / ".run.json").read_text())
        self.assertEqual(run["status"], "INCOMPLETE")
        self.assertNotEqual(run["run_id"], original["run_id"])
        self.assertEqual(json.loads((self.journal / ".result.json").read_text()), original)

    def test_two_files_remain_serial_and_target_readback_rejects_extra_entry(self):
        second = self.source / "MP3/Album/second.mp3"
        second.write_bytes(b"second audio fixture")
        self.envelope = census.collect(self.source, "source", "E0")
        self.census_path.write_text(json.dumps(self.envelope))
        self.contract["manifest_sha256"] = self.envelope["receipt"]["manifest_sha256"]
        result = self.run_stage()
        self.assertEqual(result["files"], 2)
        self.assertEqual(self.calls, ["MP3/Album/second.mp3", self.relative, None])
        (self.final.parent / "unexpected.txt").write_bytes(b"retained, never deleted")
        with self.assertRaises(stage.StageError):
            self.run_stage()
        self.assertEqual((self.final.parent / "unexpected.txt").read_bytes(), b"retained, never deleted")

    def test_production_lease_excludes_second_writer(self):
        def competing(point):
            if point == "after_pre":
                with self.assertRaises(stage.StageError):
                    self.run_stage()
        result = self.run_stage(fault=competing)
        self.assertEqual(result["files"], 1)

    def test_frozen_old_start_can_resume_but_not_start_a_new_campaign(self):
        self.run_stage()
        with patch.object(stage, "datetime", wraps=datetime) as clock:
            clock.now.return_value = datetime.now(timezone.utc) + timedelta(hours=2)
            self.assertEqual(self.run_stage()["verified_reused_this_run"], 1)
            fresh_target = self.base / "old-start-target"
            fresh_target.mkdir(mode=0o700)
            changed = copy.deepcopy(self.contract)
            changed["target"].update(root=str(fresh_target), inode=fresh_target.stat().st_ino)
            with patch.object(stage, "_observe_target"):
                with self.assertRaises(stage.StageError):
                    stage.stage_e0(changed, self.envelope)
        self.assertFalse((fresh_target / ".journal" / ".production.json").exists())

    def test_explicit_whole_census_limit_reaches_remote_final_collector(self):
        for index in range(10_000):
            (self.source / "MP3" / f"empty-{index}").mkdir()
        with patch.object(census.policy, "MAX_ITEMS", 100_000), patch.object(census.policy, "MAX_BYTES", 240_000_000):
            self.envelope = census.collect(self.source, "source", "E0")
        self.assertGreater(self.envelope["receipt"]["rows"], 10_000)
        with self.assertRaises(ValueError):
            stage.plan(self.envelope)
        self.census_path.write_text(json.dumps(self.envelope))
        self.contract.update(max_entries=100_000, manifest_sha256=self.envelope["receipt"]["manifest_sha256"])
        self.assertEqual(stage._source_request(self.contract, None)["max_entries"], 100_000)
        result = self.run_stage()
        self.assertEqual(result["status"], "E0_UNSERVED_VERIFIED")
        self.assertEqual(result["files"], 1)
        self.assertEqual(self.calls, [self.relative, None])
        self.assertEqual(self.final.read_bytes(), (self.source / self.relative).read_bytes())
        self.assertEqual((stage.policy.MAX_ITEMS, stage.policy.MAX_BYTES), (10_000, 24_000_000))

    def test_campaign_bound_is_validated_frozen_and_restored(self):
        for invalid in (0, 100_001, True, "100000"):
            changed = {**self.contract, "max_entries": invalid}
            with self.subTest(invalid=invalid), self.assertRaises(stage.StageError):
                stage.stage_e0(changed, self.envelope)
        self.assertFalse((self.target / ".journal").exists())
        with stage._envelope_bounds(100_000):
            self.assertEqual((stage.policy.MAX_ITEMS, stage.policy.MAX_BYTES), (100_000, 240_000_000))
        self.assertEqual((stage.policy.MAX_ITEMS, stage.policy.MAX_BYTES), (10_000, 24_000_000))
        self.contract["max_entries"] = 100_000
        self.run_stage()
        before = self.final.stat().st_ino
        changed = {**self.contract, "max_entries": 50_000}
        with self.assertRaises(stage.StageError):
            stage.stage_e0(changed, self.envelope)
        self.assertEqual(self.final.stat().st_ino, before)

    def test_cli_rejects_limit_conflicting_with_frozen_production_contract(self):
        self.contract["max_entries"] = 100_000
        contract_path = self.base / "extended-contract.json"
        contract_path.write_text(json.dumps(self.contract))
        contract_path.chmod(0o600)
        result = subprocess.run([sys.executable, "-I", str(STAGE), "--stage-e0", str(contract_path),
            "--census", str(self.census_path), "--max-entries", "10000"], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.target / ".journal").exists())

    def test_supported_originals_companions_playlist_and_literal_name_all_copy(self):
        additions = {"Wave/A/original.wav": b"wave original", "AIFF/A/original.aif": b"aiff original",
            "AAC/A/original.m4a": b"aac original", "AAC/A/movie.mov": b"retained movie",
            "MP3/Album/album.cue": b"retained cue", "MP3/Album/notes.nfo": b"retained info",
            "MP3/Album/album.m3u": b"track.mp3\ntrack.mp3\n",
            "MP3/Album/" + chr(0x200B) + "literal.mp3": b"literal unicode original"}
        for relative, body in additions.items():
            path = self.source / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(body)
        self.envelope = census.collect(self.source, "source", "E0")
        self.census_path.write_text(json.dumps(self.envelope))
        self.contract["manifest_sha256"] = self.envelope["receipt"]["manifest_sha256"]
        report = stage.plan(self.envelope)
        self.assertEqual(report["retained_companion_count"], 3)
        self.assertEqual(report["unresolved_count"], 0)
        result = self.run_stage()
        self.assertEqual(result["files"], 9)
        for relative, body in additions.items():
            self.assertEqual((self.target / "UNserved" / relative).read_bytes(), body)
            self.assertEqual((self.source / relative).read_bytes(), body)
        self.assertEqual(self.calls[-1], None)


if __name__ == "__main__":
    unittest.main()
