#!/usr/bin/env python3
"""Focused local-archive/idempotence checks; no native binary or network runs."""

import hashlib
import importlib.util
import io
import json
import os
import tarfile
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "chromaprint_install", ROOT / "rig/bootstrap/chromaprint/install.py"
)
INSTALL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INSTALL)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name).resolve()
        self.archive = self.home / "fixture.tar.gz"
        self.payload = bytes.fromhex("cffaedfe0c000001") + b"native-fixture"
        self.member = "chromaprint-fpcalc-1.6.2-macos-arm64/fpcalc"
        self.make_archive()

    def make_archive(self, variant=None):
        with tarfile.open(self.archive, "w:gz") as target:
            root = tarfile.TarInfo(self.member.rsplit("/", 1)[0])
            root.type, root.mode = tarfile.DIRTYPE, 0o755
            target.addfile(root)
            binary = tarfile.TarInfo(self.member)
            binary.mode, binary.size = 0o755, len(self.payload)
            if variant in ("symlink", "hardlink"):
                binary.type = (
                    tarfile.SYMTYPE if variant == "symlink" else tarfile.LNKTYPE
                )
                binary.linkname, binary.size = "elsewhere", 0
            elif variant == "traversal":
                binary.name = "../unexpected"
            target.addfile(binary, io.BytesIO(self.payload) if binary.isreg() else None)
            if variant in ("extra", "duplicate"):
                extra = tarfile.TarInfo(
                    self.member if variant == "duplicate" else "extra"
                )
                target.addfile(extra, io.BytesIO(b""))
        self.archive.chmod(0o600)
        raw = self.archive.read_bytes()
        self.pin = {
            "name": "chromaprint",
            "version": "1.6.2",
            "darwin_arm64": {
                "bytes": len(raw),
                "sha256": hashlib.sha256(raw).hexdigest(),
                "binary_member": self.member,
                "binary_bytes": len(self.payload),
                "binary_sha256": hashlib.sha256(self.payload).hexdigest(),
            },
        }

    def install(self, apply=True, host="MacBookAir"):
        with (
            patch.object(INSTALL.platform, "system", return_value="Darwin"),
            patch.object(INSTALL.platform, "machine", return_value="arm64"),
            patch.object(INSTALL.socket, "gethostname", return_value=host),
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
            return INSTALL.install(self.archive, self.pin, self.home, apply)

    def test_preview_has_no_state_and_repeat_apply_is_exact_noop(self):
        self.assertTrue(self.install(False)["dry_run"])
        self.assertFalse((self.home / ".local").exists())
        first = self.install()
        binary = Path(first["binary"])
        receipt = binary.parent / "installation.private.json"
        self.assertEqual(binary.read_bytes(), self.payload)
        self.assertEqual(binary.stat().st_mode & 0o777, 0o700)
        self.assertEqual(receipt.stat().st_mode & 0o777, 0o600)
        before = [(p.stat().st_ino, p.stat().st_mtime_ns) for p in (binary, receipt)]
        self.assertFalse(self.install()["changed"])
        self.assertEqual(
            before, [(p.stat().st_ino, p.stat().st_mtime_ns) for p in (binary, receipt)]
        )
        self.assertFalse(json.loads(receipt.read_bytes())["runtime_verified"])

    def test_archive_checksum_and_binary_pin_are_independent(self):
        self.pin["darwin_arm64"]["sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            self.install()
        self.make_archive()
        self.pin["darwin_arm64"]["binary_sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            self.install()
        self.assertFalse((self.home / ".local").exists())

    def test_unsafe_member_closures_refused(self):
        for kind in ("symlink", "hardlink", "traversal", "extra", "duplicate"):
            with self.subTest(kind=kind):
                self.make_archive(kind)
                with self.assertRaises(ValueError):
                    self.install()
        self.assertFalse((self.home / ".local").exists())

    def test_expanded_archive_bound_and_non_arm_binary_refused(self):
        with (
            patch.object(INSTALL, "MAX_BYTES", len(self.archive.read_bytes()) + 1),
            self.assertRaises(ValueError),
        ):
            self.install()
        self.payload = b"not-arm64-fixture"
        self.make_archive()
        with self.assertRaises(ValueError):
            self.install()

    def test_mbp_and_symlinked_home_parents_refused(self):
        with self.assertRaises(ValueError):
            self.install(host="w4w-mbp")
        elsewhere = self.home / "elsewhere"
        elsewhere.mkdir()
        (self.home / ".local").symlink_to(elsewhere, target_is_directory=True)
        with self.assertRaises(ValueError):
            self.install()
        self.assertEqual(list(elsewhere.iterdir()), [])

    def test_drift_partial_and_hardlinked_versions_are_held(self):
        binary = Path(self.install()["binary"])
        original = binary.read_bytes()
        binary.write_bytes(original + b"drift")
        with self.assertRaises(ValueError):
            self.install()
        binary.write_bytes(original)
        os.link(binary, self.home / "other-link")
        with self.assertRaises(ValueError):
            self.install()
        (self.home / "other-link").unlink()
        (binary.parent / "installation.private.json").unlink()
        with self.assertRaises(ValueError):
            self.install()
        self.assertFalse((binary.parent / "installation.private.json").exists())


if __name__ == "__main__":
    unittest.main()
