"""Disposable, synthetic-only tests for the review-only offload manifest."""
from __future__ import annotations

import contextlib
import errno
import importlib.util
import io
import json
import os
import stat
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

SCRIPT = Path(__file__).with_name("mba-offload-manifest.py")
spec = importlib.util.spec_from_file_location("mba_offload_manifest", SCRIPT)
collector = importlib.util.module_from_spec(spec)
import sys
sys.modules[spec.name] = collector
spec.loader.exec_module(collector)


class ManifestTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="synthetic-offload-")
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name).resolve()  # /var is a symlink on macOS
        self.root = self.base / "private-source-name"
        self.root.mkdir(mode=0o700)
        self.file = self.root / "sensitive-file-name"
        self.file.write_bytes(b"synthetic fixture")
        self.file.chmod(0o600)
        self.out = self.base / "private-output"
        self.out.mkdir(mode=0o700)

    def collect(self, roots=None, class_id="protected_local", name="manifest.json", **bounds):
        return collector.collect(roots if roots is not None else [str(self.root)],
                                 class_id, str(self.out), name, collector.Limits(**bounds))

    def assert_unknown(self, receipt, reason):
        self.assertEqual(receipt["status"], "UNKNOWN")
        self.assertEqual(receipt["reason"], reason)
        self.assertEqual(list(self.out.iterdir()), [])
        self.assertFalse(receipt["incomplete_output_may_remain"])
        self.assertEqual(receipt["reclaim_credit_bytes"], 0)
        self.assertFalse(receipt["transfer_eligible"])
        self.assertFalse(receipt["eviction_eligible"])

    @staticmethod
    def changed(st, **kwargs):
        fields = {key: getattr(st, key) for key in (
            "st_dev", "st_ino", "st_mode", "st_uid", "st_gid", "st_nlink",
            "st_size", "st_blocks", "st_flags", "st_mtime_ns", "st_ctime_ns"
        ) if hasattr(st, key)}
        fields.update(kwargs)
        return SimpleNamespace(**fields)

    def test_private_manifest_is_canonical_complete_and_only_relative_names(self):
        receipt = self.collect()
        self.assertEqual(receipt["status"], "complete")
        self.assertEqual(receipt["class_id"], "protected_local")
        self.assertFalse(receipt["incomplete_output_may_remain"])
        self.assertEqual(receipt["files"], 1)
        self.assertEqual(receipt["logical_bytes_observed"], self.file.stat().st_size)
        self.assertEqual(receipt["allocated_bytes_observed"], self.file.stat().st_blocks * 512)
        self.assertNotIn(self.file.name, json.dumps(receipt))
        self.assertNotIn(str(self.root), json.dumps(receipt))
        output = self.out / "manifest.json"
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
        raw = output.read_bytes()
        import hashlib
        self.assertEqual(receipt["sha256"], hashlib.sha256(raw).hexdigest())
        document = json.loads(raw)
        self.assertEqual(document["entries"][1]["relative_name"], self.file.name)
        self.assertEqual(document["entries"][1]["nlink"], 1)
        self.assertIn("mtime_ns", document["entries"][1])
        self.assertIn("flags", document["entries"][1])
        self.assertEqual(document["roots"][0]["device"], self.root.stat().st_dev)
        self.assertEqual(document["roots"][0]["literal_root"], str(self.root))
        self.assertTrue(document["review_only"])
        self.assertEqual(document["reclaim_credit_bytes"], 0)
        self.assertEqual(document["cross_class_overlap"], "UNKNOWN")
        self.assertEqual(receipt["cross_class_overlap"], "UNKNOWN")
        self.assertFalse(document["transfer_eligible"])
        self.assertFalse(document["eviction_eligible"])
        self.assertFalse(document["atomic_snapshot"])
        self.assertFalse(receipt["atomic_snapshot"])

    def test_exactly_four_classes_and_explicit_literal_roots(self):
        for class_id in ("neo4j_app_state", "protected_local", "downloads_unknown", "model_cache"):
            with self.subTest(class_id=class_id):
                self.assertEqual(self.collect(class_id=class_id, name=class_id + ".json")["status"], "complete")
                (self.out / (class_id + ".json")).unlink()
        self.assert_unknown(self.collect(class_id="other"), "INVALID_CLASS")
        self.assert_unknown(self.collect(roots=[]), "INVALID_ROOT")
        self.assert_unknown(self.collect(roots=["relative"]), "INVALID_ROOT")
        self.assert_unknown(self.collect(roots=[str(self.root) + "/../" + self.root.name]), "INVALID_ROOT")

    def test_nested_and_duplicate_roots_are_rejected_without_publication(self):
        child = self.root / "child"
        child.mkdir(mode=0o700)
        self.assert_unknown(self.collect(roots=[str(self.root), str(child)]), "ROOT_OVERLAP")
        self.assert_unknown(self.collect(roots=[str(self.root), str(self.root)]), "ROOT_OVERLAP")
        self.assert_unknown(self.collect(roots=[str(self.base)]), "OUTPUT_OVERLAP")

    def test_physical_output_alias_is_rejected_before_publication(self):
        real_open = collector.open_root

        def aliased(raw, *args, **kwargs):
            return real_open(self.root if os.fspath(raw) == str(self.out) else raw, *args, **kwargs)

        with mock.patch.object(collector, "open_root", side_effect=aliased):
            receipt = self.collect(name="aliased.json")
        self.assertEqual((receipt["status"], receipt["reason"]), ("UNKNOWN", "OUTPUT_OVERLAP"))
        self.assertFalse((self.root / "aliased.json").exists())

    def test_physical_nested_root_alias_is_rejected(self):
        child = self.root / "nested"
        child.mkdir(mode=0o700)
        alias = self.base / "other-literal-root"
        real_open = collector.open_root

        def aliased(raw, *args, **kwargs):
            return real_open(child if os.fspath(raw) == str(alias) else raw, *args, **kwargs)

        with mock.patch.object(collector, "open_root", side_effect=aliased):
            self.assert_unknown(self.collect(roots=[str(self.root), str(alias)]), "ROOT_OVERLAP")

    def test_entry_limit_is_shared_across_roots(self):
        second = self.base / "second"
        second.mkdir(mode=0o700)
        (second / "one").write_bytes(b"synthetic")
        self.assert_unknown(self.collect(roots=[str(self.root), str(second)], entries=1), "ENTRY_LIMIT")

    def test_symlink_ancestor_entry_and_output_are_rejected(self):
        link = self.base / "alias"
        link.symlink_to(self.root, target_is_directory=True)
        self.assert_unknown(self.collect(roots=[str(link)]), "SYMLINK")
        (self.root / "link").symlink_to(self.file)
        self.assert_unknown(self.collect(), "SYMLINK")
        (self.root / "link").unlink()
        other = self.base / "other-out"
        other.symlink_to(self.out, target_is_directory=True)
        receipt = collector.collect([str(self.root)], "protected_local", str(other), "x.json")
        self.assert_unknown(receipt, "SYMLINK")

    def test_dataless_flag_rejected_before_file_access(self):
        real = collector.os.stat
        def flagged(path, *args, **kwargs):
            st = real(path, *args, **kwargs)
            if path == self.file.name:
                return self.changed(st, st_flags=getattr(st, "st_flags", 0) | 0x40000000)
            return st
        with mock.patch.object(collector.stat, "SF_DATALESS", 0x40000000, create=True), \
             mock.patch.object(collector.os, "stat", side_effect=flagged):
            self.assert_unknown(self.collect(), "DATALESS")

    def test_hardlink_and_zero_block_ambiguity_rejected(self):
        os.link(self.file, self.root / "second-link")
        self.assert_unknown(self.collect(), "HARDLINK")
        (self.root / "second-link").unlink()
        real = collector.os.stat
        def empty_blocks(path, *args, **kwargs):
            st = real(path, *args, **kwargs)
            return self.changed(st, st_blocks=0) if path == self.file.name else st
        with mock.patch.object(collector.os, "stat", side_effect=empty_blocks):
            self.assert_unknown(self.collect(), "ALLOCATED_UNKNOWN")

    def test_unicode_case_collision_is_rejected_before_child_stat(self):
        with mock.patch.object(collector, "scan_names", return_value=[self.file.name, self.file.name.upper()]):
            self.assert_unknown(self.collect(), "NAME_COLLISION")
        with mock.patch.object(collector, "scan_names", return_value=["1", "①"]):
            self.assert_unknown(self.collect(), "NAME_COLLISION")

    def test_control_character_name_is_not_published(self):
        unsafe = self.root / "line\nbreak"
        unsafe.write_bytes(b"synthetic")
        self.assert_unknown(self.collect(), "UNSAFE_NAME")

    def test_second_pass_drift_and_root_replacement_rejected(self):
        real = collector.scan_root
        count = 0
        def drift(*args, **kwargs):
            nonlocal count
            count += 1
            rows = real(*args, **kwargs)
            if count == 2:
                rows[0]["size"] += 1
            return rows
        with mock.patch.object(collector, "scan_root", side_effect=drift):
            self.assert_unknown(self.collect(), "METADATA_DRIFT")
        real_open = collector.open_root
        calls = 0
        def replaced_root(raw, *args, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 3:
                raise OSError(errno.ENOENT, "private root disappeared")
            return real_open(raw, *args, **kwargs)
        with mock.patch.object(collector, "open_root", side_effect=replaced_root):
            self.assert_unknown(self.collect(), "OS_ERROR")

    def test_leaf_edit_after_second_pass_is_not_published_as_stable(self):
        real = collector.scan_root
        calls = 0

        def edit_leaf(*args, **kwargs):
            nonlocal calls
            rows = real(*args, **kwargs)
            calls += 1
            if calls == 2:
                os.utime(self.file, ns=(self.file.stat().st_atime_ns,
                                         self.file.stat().st_mtime_ns + 2_000_000_000))
            return rows

        with mock.patch.object(collector, "scan_root", side_effect=edit_leaf):
            self.assert_unknown(self.collect(), "METADATA_DRIFT")

    def test_output_directory_swap_during_scan_fails_closed(self):
        real = collector.scan_root
        moved = self.base / "moved-output"
        calls = 0

        def swap(*args, **kwargs):
            nonlocal calls
            rows = real(*args, **kwargs)
            calls += 1
            if calls == 1:
                self.out.rename(moved)
                self.out.mkdir(mode=0o700)
            return rows

        with mock.patch.object(collector, "scan_root", side_effect=swap):
            receipt = self.collect()
        self.assertEqual((receipt["status"], receipt["reason"]), ("UNKNOWN", "OUTPUT_DRIFT"))
        self.assertEqual(list(self.out.iterdir()), [])
        self.assertEqual(list(moved.iterdir()), [])

    def test_output_directory_swap_during_publication_retains_private_file(self):
        real_fsync = collector.os.fsync
        moved = self.base / "moved-output"
        swapped = False

        def swap_after_file_sync(fd):
            nonlocal swapped
            result = real_fsync(fd)
            if not swapped and stat.S_ISREG(os.fstat(fd).st_mode):
                self.out.rename(moved)
                self.out.mkdir(mode=0o700)
                swapped = True
            return result

        with mock.patch.object(collector.os, "fsync", side_effect=swap_after_file_sync):
            receipt = self.collect()
        self.assertEqual((receipt["status"], receipt["reason"]), ("UNKNOWN", "OUTPUT_DRIFT"))
        self.assertTrue(receipt["incomplete_output_may_remain"])
        self.assertEqual(list(self.out.iterdir()), [])
        self.assertEqual([path.name for path in moved.iterdir()], ["manifest.json"])
        self.assertEqual(stat.S_IMODE((moved / "manifest.json").stat().st_mode), 0o600)

    def test_output_filename_moved_after_write_cannot_be_complete(self):
        real_fsync = collector.os.fsync
        moved = self.out / "moved.json"
        swapped = False

        def move_created(fd):
            nonlocal swapped
            result = real_fsync(fd)
            if not swapped and stat.S_ISREG(os.fstat(fd).st_mode):
                (self.out / "manifest.json").rename(moved)
                swapped = True
            return result

        with mock.patch.object(collector.os, "fsync", side_effect=move_created):
            receipt = self.collect()
        self.assertEqual((receipt["status"], receipt["reason"]), ("UNKNOWN", "OUTPUT_DRIFT"))
        self.assertTrue(receipt["incomplete_output_may_remain"])
        self.assertFalse((self.out / "manifest.json").exists())
        self.assertTrue(moved.exists())  # displaced private output is never someone else's cleanup target

    def test_failed_write_does_not_unlink_a_replacement_output(self):
        sentinel = self.out / "sentinel.json"
        sentinel.write_bytes(b"preexisting-sentinel")
        moved = self.out / "created-moved.json"

        def substitute(fd):
            if stat.S_ISREG(os.fstat(fd).st_mode):
                (self.out / "manifest.json").rename(moved)
                sentinel.rename(self.out / "manifest.json")
                raise OSError(errno.EIO, "synthetic output error")
            return None

        with mock.patch.object(collector.os, "fsync", side_effect=substitute):
            receipt = self.collect()
        self.assertEqual((receipt["status"], receipt["reason"]), ("UNKNOWN", "OUTPUT_DRIFT"))
        self.assertTrue(receipt["incomplete_output_may_remain"])
        self.assertEqual((self.out / "manifest.json").read_bytes(), b"preexisting-sentinel")
        self.assertTrue(moved.exists())

    def test_failed_write_replacement_after_identity_check_is_never_unlinked(self):
        sentinel = self.out / "sentinel.json"
        sentinel.write_bytes(b"preexisting-sentinel")
        sentinel_stat = sentinel.stat()
        output = self.out / "manifest.json"
        moved = self.out / "created-moved.json"
        real_matches = collector.output_matches
        checked = []

        def substitute_after_check(*args):
            matched = real_matches(*args)
            checked.append(matched)
            output.rename(moved)
            sentinel.rename(output)
            return matched

        with mock.patch.object(collector.os, "fsync", side_effect=OSError(errno.EIO, "synthetic output error")), \
             mock.patch.object(collector, "output_matches", side_effect=substitute_after_check), \
             mock.patch.object(collector.os, "unlink", wraps=collector.os.unlink) as unlink:
            receipt = self.collect()
        self.assertEqual(checked, [True])  # substitution occurs after a successful identity check
        self.assertEqual((receipt["status"], receipt["reason"]), ("UNKNOWN", "OS_ERROR"))
        self.assertIsNone(receipt["sha256"])
        self.assertTrue(receipt["incomplete_output_may_remain"])
        self.assertEqual(output.read_bytes(), b"preexisting-sentinel")
        self.assertEqual((output.stat().st_dev, output.stat().st_ino),
                         (sentinel_stat.st_dev, sentinel_stat.st_ino))
        self.assertTrue(moved.exists())
        self.assertEqual(stat.S_IMODE(moved.stat().st_mode), 0o600)
        unlink.assert_not_called()
        self.assertEqual(self.file.read_bytes(), b"synthetic fixture")

    def test_created_output_content_change_cannot_match_public_hash(self):
        real_fsync = collector.os.fsync
        changed = False

        def change_after_directory_sync(fd):
            nonlocal changed
            result = real_fsync(fd)
            if not changed and stat.S_ISDIR(os.fstat(fd).st_mode):
                with (self.out / "manifest.json").open("r+b") as output:
                    output.write(b"X")
                changed = True
            return result

        with mock.patch.object(collector.os, "fsync", side_effect=change_after_directory_sync):
            receipt = self.collect()
        self.assertEqual((receipt["status"], receipt["reason"]), ("UNKNOWN", "OUTPUT_DRIFT"))
        self.assertTrue(receipt["incomplete_output_may_remain"])
        self.assertEqual(stat.S_IMODE((self.out / "manifest.json").stat().st_mode), 0o600)

    def test_output_directory_privacy_drift_fails_closed(self):
        real_scan = collector.scan_root
        changed = False

        def loosen(*args, **kwargs):
            nonlocal changed
            rows = real_scan(*args, **kwargs)
            if not changed:
                self.out.chmod(0o755)
                changed = True
            return rows

        with mock.patch.object(collector, "scan_root", side_effect=loosen):
            self.assert_unknown(self.collect(), "OUTPUT_PRIVACY")

    def test_output_directory_acl_blocks_creation(self):
        with mock.patch.object(
            collector,
            "output_acl_absent",
            side_effect=lambda fd: not stat.S_ISDIR(os.fstat(fd).st_mode),
        ) as inspect:
            self.assert_unknown(self.collect(), "OUTPUT_PRIVACY")
        self.assertEqual(inspect.call_count, 1)

    def test_inherited_output_file_acl_blocks_payload_write(self):
        with mock.patch.object(
            collector,
            "output_acl_absent",
            side_effect=lambda fd: not stat.S_ISREG(os.fstat(fd).st_mode),
        ):
            receipt = self.collect()
        self.assertEqual(
            (receipt["status"], receipt["reason"]), ("UNKNOWN", "OUTPUT_PRIVACY")
        )
        self.assertIsNone(receipt["sha256"])
        self.assertTrue(receipt["incomplete_output_may_remain"])
        output = self.out / "manifest.json"
        self.assertTrue(output.exists())
        # No payload write before ACL inspection.
        self.assertEqual(output.stat().st_size, 0)
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)

    def test_acl_inspection_error_fails_closed(self):
        def denied(fd, acl_type):
            self.assertEqual(acl_type, 0x100)
            collector.ctypes.set_errno(errno.EACCES)

        libc = SimpleNamespace(
            acl_get_fd_np=mock.Mock(side_effect=denied), acl_free=mock.Mock()
        )
        with (
            mock.patch.object(collector.sys, "platform", "darwin"),
            mock.patch.object(collector.ctypes, "CDLL", return_value=libc),
        ):
            self.assert_unknown(self.collect(), "OUTPUT_PRIVACY")
        libc.acl_get_fd_np.assert_called_once()
        libc.acl_free.assert_not_called()

    def test_fd_acl_api_rejects_returned_acl(self):
        libc = SimpleNamespace(
            acl_get_fd_np=mock.Mock(return_value=1), acl_free=mock.Mock(return_value=0)
        )
        with (
            mock.patch.object(collector.sys, "platform", "darwin"),
            mock.patch.object(collector.ctypes, "CDLL", return_value=libc),
        ):
            self.assert_unknown(self.collect(), "OUTPUT_PRIVACY")
        libc.acl_free.assert_called_once_with(1)

    def test_output_acl_final_recheck_fails_closed(self):
        real_fsync = collector.os.fsync

        def check_target(target):
            present = False
            name = target + ".json"

            def reveal_after_directory_sync(fd):
                nonlocal present
                result = real_fsync(fd)
                if stat.S_ISDIR(os.fstat(fd).st_mode):
                    present = True
                return result

            def inspect(fd):
                mode = os.fstat(fd).st_mode
                return not (
                    present
                    and (
                        stat.S_ISDIR(mode)
                        if target == "directory"
                        else stat.S_ISREG(mode)
                    )
                )

            with (
                mock.patch.object(
                    collector.os, "fsync", side_effect=reveal_after_directory_sync
                ),
                mock.patch.object(collector, "output_acl_absent", side_effect=inspect),
            ):
                receipt = self.collect(name=name)
            self.assertTrue(present)
            self.assertEqual(
                (receipt["status"], receipt["reason"]), ("UNKNOWN", "OUTPUT_PRIVACY")
            )
            self.assertIsNone(receipt["sha256"])
            self.assertTrue(receipt["incomplete_output_may_remain"])
            self.assertTrue((self.out / name).exists())

        for target in ("directory", "file"):
            with self.subTest(target=target):
                check_target(target)

    def test_permission_cross_volume_and_os_errors_are_unknown(self):
        for error in (errno.EACCES, errno.EDEADLK):
            with self.subTest(error=error), mock.patch.object(collector, "scan_names", side_effect=OSError(error, "secret")):
                self.assert_unknown(self.collect(), "OS_ERROR")
        real = collector.os.stat
        def other_volume(path, *args, **kwargs):
            st = real(path, *args, **kwargs)
            return self.changed(st, st_dev=st.st_dev + 1) if path == self.file.name else st
        with mock.patch.object(collector.os, "stat", side_effect=other_volume):
            self.assert_unknown(self.collect(), "VOLUME_SWITCH")

    def test_entry_depth_bytes_and_soft_time_limits(self):
        extra = self.root / "extra"
        extra.write_bytes(b"synthetic")
        extra.chmod(0o600)
        self.assert_unknown(self.collect(entries=1), "ENTRY_LIMIT")
        extra.unlink()
        child = self.root / "nested"
        child.mkdir(mode=0o700)
        self.assert_unknown(self.collect(depth=0), "DEPTH_LIMIT")
        child.rmdir()
        self.assert_unknown(self.collect(manifest_bytes=32), "MANIFEST_LIMIT")
        count = 0
        def clock():
            nonlocal count
            count += 1
            return float(count)
        receipt = collector.collect([str(self.root)], "model_cache", str(self.out), "x.json",
                                    collector.Limits(seconds=0.5), clock=clock)
        self.assert_unknown(receipt, "DEADLINE")

    def test_deadline_expiring_during_final_digest_is_unknown(self):
        now = 0.0
        real_sha256 = collector.hashlib.sha256

        def late_digest(payload):
            nonlocal now
            now = 6.0
            return real_sha256(payload)

        with mock.patch.object(collector.hashlib, "sha256", side_effect=late_digest):
            receipt = collector.collect([str(self.root)], "protected_local", str(self.out),
                                        "manifest.json", collector.Limits(seconds=5), clock=lambda: now)
        self.assertEqual((receipt["status"], receipt["reason"]), ("UNKNOWN", "DEADLINE"))
        self.assertTrue(receipt["incomplete_output_may_remain"])
        self.assertTrue((self.out / "manifest.json").exists())

    def test_deadline_expiring_in_final_output_directory_close_is_unknown(self):
        now = 0.0
        output_fd = None
        output_opens = 0
        real_open = collector.open_root
        real_close = collector.os.close

        def track_output(raw, *args, **kwargs):
            nonlocal output_fd, output_opens
            fd = real_open(raw, *args, **kwargs)
            if os.fspath(raw) == str(self.out):
                output_opens += 1
                if output_opens == 1:  # first output open is the pinned publication fd
                    output_fd = fd
            return fd

        def delayed_close(fd):
            nonlocal now
            result = real_close(fd)
            if fd == output_fd:
                now = 6.0
            return result

        with (
            mock.patch.object(collector, "open_root", side_effect=track_output),
            mock.patch.object(collector.os, "close", side_effect=delayed_close),
        ):
            receipt = collector.collect(
                [str(self.root)],
                "protected_local",
                str(self.out),
                "manifest.json",
                collector.Limits(seconds=5),
                clock=lambda: now,
            )
        self.assertIsNotNone(output_fd)
        self.assertEqual(
            (receipt["status"], receipt["reason"]), ("UNKNOWN", "DEADLINE")
        )
        self.assertIsNone(receipt["sha256"])
        self.assertTrue(receipt["incomplete_output_may_remain"])
        self.assertTrue((self.out / "manifest.json").exists())

    def test_final_output_directory_close_error_stays_os_error(self):
        output_fd = None
        output_opens = 0
        real_open = collector.open_root
        real_close = collector.os.close

        def track_output(raw, *args, **kwargs):
            nonlocal output_fd, output_opens
            fd = real_open(raw, *args, **kwargs)
            if os.fspath(raw) == str(self.out):
                output_opens += 1
                if output_opens == 1:  # first output open is the pinned publication fd
                    output_fd = fd
            return fd

        def failed_close(fd):
            real_close(fd)
            if fd == output_fd:
                raise OSError(errno.EIO, "synthetic close error")

        with (
            mock.patch.object(collector, "open_root", side_effect=track_output),
            mock.patch.object(collector.os, "close", side_effect=failed_close),
        ):
            receipt = self.collect()
        self.assertIsNotNone(output_fd)
        self.assertEqual(
            (receipt["status"], receipt["reason"]), ("UNKNOWN", "OS_ERROR")
        )
        self.assertIsNone(receipt["sha256"])
        self.assertTrue(receipt["incomplete_output_may_remain"])
        self.assertTrue((self.out / "manifest.json").exists())

    def test_private_directory_and_output_name_validation(self):
        self.out.chmod(0o755)
        self.assert_unknown(self.collect(), "OUTPUT_PRIVACY")
        self.out.chmod(0o700)
        self.assert_unknown(self.collect(name="../escape"), "INVALID_OUTPUT")
        self.assert_unknown(self.collect(name=".hidden"), "INVALID_OUTPUT")

    def test_exclusive_creation_never_overwrites_existing_manifest(self):
        existing = self.out / "manifest.json"
        existing.write_bytes(b"untouched")
        receipt = self.collect()
        self.assertEqual(receipt["status"], "UNKNOWN")
        self.assertEqual(receipt["reason"], "OUTPUT_EXISTS")
        self.assertEqual(existing.read_bytes(), b"untouched")

    def test_failed_output_fsync_never_unlinks_exposed_name(self):
        with mock.patch.object(collector.os, "fsync", side_effect=OSError(errno.EIO, "private path")), \
             mock.patch.object(collector.os, "unlink", side_effect=AssertionError("unsafe unlink")) as unlink:
            receipt = self.collect()
        self.assertEqual((receipt["status"], receipt["reason"]), ("UNKNOWN", "OS_ERROR"))
        self.assertTrue(receipt["incomplete_output_may_remain"])
        self.assertEqual(stat.S_IMODE((self.out / "manifest.json").stat().st_mode), 0o600)
        unlink.assert_not_called()
        self.assertTrue(self.file.exists())

    def test_deadline_expiring_during_output_fsync_is_unknown(self):
        real_fsync = collector.os.fsync
        for kind in ("file", "directory"):
            with self.subTest(kind=kind):
                now = 0.0
                expired = []
                name = kind + ".json"

                def expire(fd):
                    nonlocal now
                    result = real_fsync(fd)
                    mode = os.fstat(fd).st_mode
                    if ((kind == "file" and stat.S_ISREG(mode))
                            or (kind == "directory" and stat.S_ISDIR(mode))):
                        now = 6.0
                        expired.append(kind)
                    return result

                with mock.patch.object(collector.os, "fsync", side_effect=expire):
                    receipt = collector.collect([str(self.root)], "protected_local", str(self.out),
                                                name, collector.Limits(seconds=5), clock=lambda: now)
                self.assertEqual(expired, [kind])
                self.assertEqual((receipt["status"], receipt["reason"]), ("UNKNOWN", "DEADLINE"))
                self.assertIsNone(receipt["sha256"])
                self.assertTrue(receipt["incomplete_output_may_remain"])
                self.assertEqual(receipt["reclaim_credit_bytes"], 0)
                self.assertFalse(receipt["transfer_eligible"])
                self.assertFalse(receipt["eviction_eligible"])
                output = self.out / name
                self.assertTrue(output.exists())
                self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)

    def test_root_symlink_swap_at_open_is_fail_closed(self):
        real_open = collector.os.open
        def swapped(path, flags, *args, **kwargs):
            if path == self.root.name:
                raise OSError(errno.ELOOP, "private path")
            return real_open(path, flags, *args, **kwargs)
        with mock.patch.object(collector.os, "open", side_effect=swapped):
            self.assert_unknown(self.collect(), "SYMLINK")

    def test_normal_source_permissions_allow_metadata_but_missing_output_fails_closed(self):
        self.file.chmod(0o644)
        self.root.chmod(0o755)
        self.assertEqual(self.collect()["status"], "complete")
        (self.out / "manifest.json").unlink()
        self.out.rmdir()
        receipt = self.collect()
        self.assertEqual((receipt["status"], receipt["reason"]), ("UNKNOWN", "OS_ERROR"))

    def test_no_regular_file_body_open_or_source_mutation(self):
        original = self.file.read_bytes()
        real_open = collector.os.open
        attempted = []
        def guarded(path, flags, *args, **kwargs):
            attempted.append((path, flags))
            if path == self.file.name or path == str(self.file):
                self.fail("regular-file body was opened")
            return real_open(path, flags, *args, **kwargs)
        with mock.patch.object(collector.os, "open", side_effect=guarded):
            self.assertEqual(self.collect()["status"], "complete")
        self.assertEqual(self.file.read_bytes(), original)
        self.assertTrue(all(flags & os.O_DIRECTORY or flags & os.O_EXCL for _, flags in attempted))
        self.assertFalse(any(hasattr(collector, name) for name in ("copy", "delete", "upload", "apply", "hydrate")))

    def test_cli_requires_ack_and_redacts_failure_and_success(self):
        common = ["--class-id", "protected_local", "--root", str(self.root),
                  "--output-dir", str(self.out), "--output-name", "cli.json"]
        for args, expected in ((common, 2), (common + ["--ack-soft-deadline"], 0),
                               (common + ["--ack-soft-deadline"], 1)):
            with self.subTest(expected=expected):
                out, err = io.StringIO(), io.StringIO()
                with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                    code = collector.main(args)
                self.assertEqual(code, expected)
                combined = out.getvalue() + err.getvalue()
                self.assertNotIn(str(self.base), combined)
                self.assertNotIn(self.file.name, combined)
                if code != 2:
                    self.assertEqual(json.loads(out.getvalue())["review_only"], True)


if __name__ == "__main__":
    unittest.main()
