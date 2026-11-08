"""Synthetic temp-root tests for the metadata-only retained inventory."""

from __future__ import annotations

import errno
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

SCRIPT = Path(__file__).with_name("mba-retained-inventory.py")
spec = importlib.util.spec_from_file_location("mba_retained_inventory", SCRIPT)
collector = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = collector
spec.loader.exec_module(collector)


class InventoryTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="synthetic-retained-")
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()  # macOS /var is a symlink
        self.root = self.base / "private-retained-name"
        self.root.mkdir()
        (self.root / "sample.dat").write_bytes(b"metadata only")

    def collect(self, *roots: Path, **options):
        return collector.collect(roots or (self.root,), collector.Limits(**options))

    def reason(self, document, index=0):
        return document["roots"][index]["issue"]["reason"]

    @staticmethod
    def replaced(entry, **changes):
        fields = {key: getattr(entry, key) for key in (
            "st_dev", "st_ino", "st_mode", "st_size", "st_mtime_ns", "st_ctime_ns",
            "st_blocks", "st_flags") if hasattr(entry, key)}
        fields.update(changes)
        return SimpleNamespace(**fields)

    def test_complete_stable_receipt_is_redacted_and_never_opens_file(self):
        actual_open = collector.os.open
        flags_seen = []

        def observed_open(path, flags, *args, **kwargs):
            flags_seen.append(flags)
            return actual_open(path, flags, *args, **kwargs)

        with mock.patch.object(collector.os, "open", side_effect=observed_open):
            first = self.collect()
        second = self.collect()
        self.assertEqual(first, second)
        self.assertEqual(first["status"], "complete")
        self.assertEqual(first["roots"][0]["status"], "complete")
        self.assertEqual(first["roots"][0]["entries_observed"], 1)
        self.assertTrue(all(flags & os.O_DIRECTORY and flags & os.O_NOFOLLOW for flags in flags_seen))
        self.assertGreater(first["roots"][0]["logical_bytes_observed"], 0)
        self.assertEqual(first["aggregate"]["status"], "UNKNOWN")
        self.assertNotIn(str(self.base), json.dumps(first))
        self.assertNotIn("sample.dat", json.dumps(first))
        self.assertFalse(first["hard_syscall_timeout"])
        self.assertEqual(first["roots"][0]["root_identity"]["device"], self.root.stat().st_dev)
        self.assertEqual(first["roots"][0]["volume_identity"]["apfs_volume_uuid"], "UNKNOWN")

    def test_symlink_root_and_ancestor_never_follow(self):
        alias = self.base / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        parent_alias = self.base / "parent-alias"
        parent_alias.symlink_to(self.base, target_is_directory=True)
        for root in (alias, parent_alias / self.root.name):
            with self.subTest(root=root):
                result = self.collect(root)
                self.assertEqual(result["status"], "UNKNOWN")
                self.assertEqual(self.reason(result), "OS_ERROR")
                self.assertIn(result["roots"][0]["issue"]["errno"], (errno.ELOOP, errno.ENOTDIR))

    def test_child_symlink_and_incomplete_child_aggregate(self):
        (self.root / "link").symlink_to(self.base, target_is_directory=True)
        second = self.base / "other"
        second.mkdir()
        (second / "file").write_bytes(b"ok")
        result = self.collect(self.root, second)
        self.assertEqual(self.reason(result), "SYMLINK")
        self.assertEqual(result["roots"][0]["status"], "UNKNOWN")
        self.assertEqual(result["roots"][1]["status"], "complete")
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertEqual(result["aggregate"]["unique_allocated_bytes"], "UNKNOWN")

    def test_hardlinks_are_deduplicated_within_root_but_not_claimed_reclaimable(self):
        source = self.root / "sample.dat"
        alias = self.root / "linked.dat"
        os.link(source, alias)
        result = self.collect()
        row = result["roots"][0]
        self.assertEqual(row["entries_observed"], 2)
        self.assertEqual(row["objects_counted"], 2)  # root directory + one inode
        self.assertEqual(row["logical_bytes_observed"], self.root.stat().st_size + source.stat().st_size)
        self.assertEqual(row["allocated_bytes_observed"],
                         (self.root.stat().st_blocks + source.stat().st_blocks) * 512)
        self.assertEqual(result["aggregate"]["reclaimable_bytes"], "UNKNOWN")

    def test_nonempty_zero_blocks_and_injected_dataless_flags_are_unknown(self):
        actual_stat = collector.os.stat

        def zero_blocks(path, *args, **kwargs):
            entry = actual_stat(path, *args, **kwargs)
            if path == "sample.dat":
                return self.replaced(entry, st_blocks=0)
            return entry

        with mock.patch.object(collector.os, "stat", side_effect=zero_blocks):
            result = self.collect()
        self.assertEqual(self.reason(result), "ALLOCATED_UNKNOWN")
        self.assertEqual(result["roots"][0]["objects_counted"], 1)
        self.assertEqual(result["status"], "UNKNOWN")

        # Synthetic SF_DATALESS is injected without contacting any provider.
        with mock.patch.object(collector.stat, "SF_DATALESS", 0x40000000, create=True):
            def dataless(path, *args, **kwargs):
                entry = actual_stat(path, *args, **kwargs)
                if path == "sample.dat":
                    return self.replaced(entry, st_flags=getattr(entry, "st_flags", 0) | 0x40000000)
                return entry

            with mock.patch.object(collector.os, "stat", side_effect=dataless):
                result = self.collect()
        self.assertEqual(self.reason(result), "DATALESS")
        self.assertEqual(result["status"], "UNKNOWN")

    def test_dataless_root_is_rejected_before_its_directory_open(self):
        actual_stat = collector.os.stat
        actual_open = collector.os.open
        opened = []

        def flagged_root(path, *args, **kwargs):
            entry = actual_stat(path, *args, **kwargs)
            if path == self.root.name:
                return self.replaced(entry, st_flags=getattr(entry, "st_flags", 0) | 0x40000000)
            return entry

        def track_open(path, flags, *args, **kwargs):
            opened.append(path)
            return actual_open(path, flags, *args, **kwargs)

        with mock.patch.object(collector.stat, "SF_DATALESS", 0x40000000, create=True), \
             mock.patch.object(collector.os, "stat", side_effect=flagged_root), \
             mock.patch.object(collector.os, "open", side_effect=track_open):
            result = self.collect()
        self.assertEqual(self.reason(result), "DATALESS")
        self.assertNotIn(self.root.name, opened)

    def test_mocked_nested_volume_switch(self):
        same_volume = collector.same_volume
        with mock.patch.object(collector, "same_volume",
                               side_effect=lambda st, dev: False if st.st_ino == (self.root / "sample.dat").stat().st_ino
                               else same_volume(st, dev)):
            result = self.collect()
        self.assertEqual(self.reason(result), "VOLUME_SWITCH")
        self.assertEqual(result["roots"][0]["issue"]["errno"], errno.EXDEV)

    def test_deadlock_and_permission_never_become_complete_or_zero(self):
        for code in (errno.EDEADLK, errno.EACCES):
            with self.subTest(code=code), mock.patch.object(
                collector, "scan_names", side_effect=OSError(code, "private path must not escape")
            ):
                result = self.collect()
                self.assertEqual(result["status"], "UNKNOWN")
                self.assertEqual(result["roots"][0]["issue"],
                                 {"reason": "OS_ERROR", "errno": code})
                self.assertNotIn("private path", json.dumps(result))

    def test_soft_deadline_is_unknown_not_hard_syscall_timeout(self):
        ticks = 0

        def fake_clock():
            nonlocal ticks
            ticks += 1
            return ticks * 0.01

        result = collector.collect([self.root], collector.Limits(seconds=0.005), clock=fake_clock)
        self.assertEqual(self.reason(result), "DEADLINE")
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertFalse(result["hard_syscall_timeout"])

    def test_each_root_gets_its_own_soft_deadline(self):
        now = 0.0
        second = self.base / "second"
        second.mkdir()

        def clock():
            return now

        def synthetic_root(raw, index, limits, tick):
            nonlocal now
            tick()
            now += 0.8
            tick()
            row = collector.empty_root(index)
            row["status"] = "complete"
            return row

        with mock.patch.object(collector, "census_root", side_effect=synthetic_root):
            result = collector.collect((self.root, second), collector.Limits(seconds=1.0), clock=clock)
        self.assertEqual(result["status"], "complete")
        self.assertEqual([row["status"] for row in result["roots"]], ["complete", "complete"])

    def test_entry_depth_and_root_count_bounds(self):
        (self.root / "extra").write_bytes(b"x")
        self.assertEqual(self.reason(self.collect(entries=1)), "ENTRY_LIMIT")
        (self.root / "child").mkdir()
        (self.root / "child" / "grandchild").mkdir()
        self.assertEqual(self.reason(self.collect(depth=1)), "DEPTH_LIMIT")
        with self.assertRaises(ValueError):
            self.collect(*([self.root] * (collector.MAX_ROOTS + 1)))
        with self.assertRaises(ValueError):
            self.collect(entries=collector.MAX_ENTRIES + 1)
        self.assertEqual(self.reason(self.collect(self.root / ".." / self.root.name)), "INVALID_ROOT")

    def test_cli_requires_ack_and_returns_redacted_unknown_receipt(self):
        command = [sys.executable, "-I", str(SCRIPT), "--root", str(self.root)]
        missing = subprocess.run(command, capture_output=True, text=True, timeout=10)
        self.assertNotEqual(missing.returncode, 0)
        self.assertNotIn(str(self.root), missing.stderr)
        (self.root / "link").symlink_to(self.base, target_is_directory=True)
        result = subprocess.run(command + ["--ack-soft-deadline"],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "UNKNOWN")
        self.assertNotIn(str(self.root), result.stdout)


if __name__ == "__main__":
    unittest.main()
