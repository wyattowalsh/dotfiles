#!/usr/bin/env python3
"""Focused slskd installer tests; never call real launchctl or the network."""

import hashlib
import importlib.util
import json
import os
import plistlib
import tempfile
import time
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "slskd_install", ROOT / "rig/bootstrap/slskd/install.py"
)
INSTALL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INSTALL)
INTAKE_SPEC = importlib.util.spec_from_file_location(
    "slskd_intake", ROOT / "rig/bootstrap/slskd/intake.py"
)
INTAKE = importlib.util.module_from_spec(INTAKE_SPEC)
INTAKE_SPEC.loader.exec_module(INTAKE)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.archive = self.home / "fixture.zip"
        with zipfile.ZipFile(self.archive, "w") as z:
            z.writestr("slskd", b"native-fixture")
            z.writestr("wwwroot/index.html", b"web-fixture")
        self.pin = {
            "version": "0.26.2",
            "darwin_arm64": {
                "sha256": hashlib.sha256(self.archive.read_bytes()).hexdigest()
            },
        }

    def apply(self, **kwargs):
        with (
            patch.object(INSTALL.platform, "system", return_value="Darwin"),
            patch.object(INSTALL.platform, "machine", return_value="arm64"),
            patch.object(
                INSTALL.pwd,
                "getpwuid",
                return_value=SimpleNamespace(pw_dir=str(self.home)),
            ),
            patch.object(
                INSTALL.shutil,
                "disk_usage",
                return_value=SimpleNamespace(free=64 * INSTALL.GIB),
            ),
            patch.object(INSTALL, "loaded", return_value=kwargs.pop("loaded", False)),
        ):
            return INSTALL.install(
                self.archive,
                self.pin,
                self.home,
                kwargs.pop("create", True),
                kwargs.pop("start", False),
            )

    def test_prepare_then_idempotent_no_activation_or_secret_output(self):
        first = self.apply()
        state = self.home / ".local/share/slskd"
        private = state / "credentials.private.json"
        original = private.read_bytes()
        second = self.apply(loaded=True)
        self.assertEqual(private.read_bytes(), original)
        credentials = json.loads(original)
        for value in (
            credentials["web_password"],
            credentials["network_password"],
            credentials["jwt_key"],
        ):
            self.assertNotIn(value, json.dumps(first))
            self.assertNotIn(value, json.dumps(second))
        self.assertFalse((self.home / "Library/LaunchAgents").exists())
        self.assertFalse(first["start_requested"])
        self.assertEqual(private.stat().st_mode & 0o777, 0o600)
        intake = state / "intake.py"
        self.assertEqual(intake.read_bytes(), INSTALL.INTAKE_SOURCE.read_bytes())
        self.assertEqual(intake.stat().st_mode & 0o777, 0o600)
        receipt = json.loads((state / "installation.private.json").read_bytes())
        self.assertEqual(receipt["managed_files"]["intake.py"], INSTALL.digest(intake))
        config = json.loads((state / "slskd.yml").read_text())
        self.assertEqual(config["web"]["ip_address"], "127.0.0.1")
        self.assertTrue(config["web"]["https"]["disabled"])
        self.assertEqual(config["web"]["content_path"], "wwwroot")
        self.assertFalse(Path(config["web"]["content_path"]).is_absolute())
        self.assertFalse(config["remote_configuration"])
        self.assertFalse(config["remote_file_management"])
        self.assertEqual(config["shares"]["directories"], [])
        self.assertNotIn("Soulseek Downloads", config["directories"]["downloads"])
        launch = plistlib.loads((state / "launchagent.plist").read_bytes())
        self.assertTrue(
            (
                Path(launch["WorkingDirectory"])
                / config["web"]["content_path"]
                / "index.html"
            ).is_file()
        )
        self.assertEqual(launch["ProgramArguments"], [str(state / "run")])
        self.assertNotIn("UserName", launch)

    def test_hash_mismatch_prevents_extract(self):
        self.pin["darwin_arm64"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            INSTALL.checked_archive(self.archive, self.pin)

    def test_unsafe_archive_path_rejected_even_when_hash_matches(self):
        with zipfile.ZipFile(self.archive, "a") as z:
            z.writestr("../outside", "bad")
        self.pin["darwin_arm64"]["sha256"] = INSTALL.digest(self.archive)
        with self.assertRaisesRegex(ValueError, "unsafe"):
            INSTALL.checked_archive(self.archive, self.pin)

    def test_running_configuration_drift_is_not_overwritten(self):
        self.apply()
        state = self.home / ".local/share/slskd"
        config = state / "slskd.yml"
        config.write_text("changed")
        with self.assertRaisesRegex(ValueError, "running service differs"):
            self.apply(loaded=True)
        self.assertEqual(config.read_text(), "changed")

    def test_existing_binary_drift_is_not_overwritten(self):
        self.apply()
        binary = self.home / ".local/share/slskd/versions/0.26.2/slskd"
        binary.write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "existing pinned version differs"):
            self.apply()
        self.assertEqual(binary.read_bytes(), b"changed")

    def test_credentials_must_remain_owner_only(self):
        self.apply()
        private = self.home / ".local/share/slskd/credentials.private.json"
        private.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "0600"):
            self.apply()

    def test_first_account_provision_is_explicit(self):
        with self.assertRaisesRegex(ValueError, "explicit --create-credentials"):
            self.apply(create=False)

    def test_start_is_separate_from_install(self):
        self.apply()
        with (
            patch.object(INSTALL.subprocess, "run") as run,
            patch.object(INSTALL, "loaded", side_effect=[False, True, True]),
            patch.object(INSTALL.platform, "system", return_value="Darwin"),
            patch.object(INSTALL.platform, "machine", return_value="arm64"),
            patch.object(
                INSTALL.pwd,
                "getpwuid",
                return_value=SimpleNamespace(pw_dir=str(self.home)),
            ),
            patch.object(
                INSTALL.shutil,
                "disk_usage",
                return_value=SimpleNamespace(free=64 * INSTALL.GIB),
            ),
        ):
            INSTALL.install(self.archive, self.pin, self.home, False, True)
        run.assert_called_once()
        self.assertEqual(run.call_args.args[0][1], "bootstrap")
        self.assertTrue(
            (self.home / "Library/LaunchAgents/com.wyattowalsh.slskd.plist").exists()
        )


class IntakeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.completed = self.root / "completed"
        self.completed.mkdir()
        self.audio = self.completed / "track.flac"
        self.audio.write_bytes(b"fixture-audio")
        os.utime(self.audio, (time.time() - 60, time.time() - 60))
        transfer = {
            "id": "724ea77a-d53a-473f-bd3b-9300e3bf3109",
            "direction": "Download",
            "state": "Completed, Succeeded",
            "username": "fixture-peer",
            "filename": "remote\\release\\track.flac",
            "size": self.audio.stat().st_size,
            "bytesTransferred": self.audio.stat().st_size,
            "endedAt": "2026-10-31T01:00:00Z",
            "removed": False,
            "exception": None,
        }
        self.data = {
            "version": 0,
            "localFilename": str(self.audio),
            "remoteFilename": transfer["filename"],
            "transfer": transfer,
        }

    def record(self):
        return {
            "type": "DownloadFileComplete",
            "id": "6833ca16-d180-4861-a65d-b5e7e3354ae0",
            "timestamp": "2026-10-31T01:00:00Z",
            "data": json.dumps(self.data),
        }

    def test_stage_is_review_required_and_duplicate_report_is_idempotent(self):
        item = INTAKE.candidate(self.record(), self.completed)
        self.assertEqual(item["identity_status"], "review_required")
        self.assertFalse(item["format_verified"])
        self.assertFalse(item["canonical_effects"])
        self.assertEqual(INTAKE.stage(item, self.root), "staged")
        self.assertEqual(INTAKE.stage(item, self.root), "reused")
        self.assertEqual(self.audio.read_bytes(), b"fixture-audio")
        item["file_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "conflicts"):
            INTAKE.stage(item, self.root)

    def test_raw_successful_transfer_is_not_completion_proof(self):
        self.assertIsNone(INTAKE.candidate(self.data["transfer"], self.completed))

    def test_outside_completion_path_is_rejected(self):
        self.data["localFilename"] = str(self.root / "outside.flac")
        with self.assertRaisesRegex(ValueError, "outside"):
            INTAKE.candidate(self.record(), self.completed)

    def test_unsettled_file_is_held(self):
        os.utime(self.audio)
        with self.assertRaisesRegex(ValueError, "not settled"):
            INTAKE.candidate(self.record(), self.completed)

    def test_symlinked_completion_is_rejected(self):
        link = self.completed / "link.flac"
        link.symlink_to(self.audio)
        self.data["localFilename"] = str(link)
        with self.assertRaisesRegex(ValueError, "symlinked"):
            INTAKE.candidate(self.record(), self.completed)

    def test_failed_partial_removed_and_wrong_size_are_rejected(self):
        for key, value in (
            ("state", "Completed, Errored"),
            ("bytesTransferred", 1),
            ("removed", True),
        ):
            with self.subTest(key=key):
                old = self.data["transfer"][key]
                self.data["transfer"][key] = value
                with self.assertRaises(ValueError):
                    INTAKE.candidate(self.record(), self.completed)
                self.data["transfer"][key] = old


if __name__ == "__main__":
    unittest.main()
