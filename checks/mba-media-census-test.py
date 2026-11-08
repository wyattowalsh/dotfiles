"""Offline temp-root tests for the independent, read-only media census."""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).with_name("mba-media-census.py")


def load_collector():
    spec = importlib.util.spec_from_file_location("synthetic_media_census", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class MediaCensusTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="synthetic-media-census-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve() / "library"
        self.root.mkdir()
        (self.root / "MP3" / "A").mkdir(parents=True)
        (self.root / "Playlists").mkdir()
        (self.root / "MP3" / "A" / "song.mp3").write_bytes(b"abc")
        (self.root / "MP3" / "A" / "song.lrc").write_bytes(b"lyric")
        (self.root / "Playlists" / "mix.m3u").write_text("#EXTM3U\nMP3/A/song.mp3\n", encoding="utf-8")

    def invoke(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "-I", str(SCRIPT), "--root", str(self.root),
             "--role", "source", "--epoch", "E0", *arguments],
            capture_output=True, text=True, timeout=15, check=False,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
        )

    def test_self_asserted_dfs_manifest_matches_without_order_sensitivity(self) -> None:
        # Lexical ordering places A.mp3 before A/song.mp3; DFS emits it after.
        (self.root / "MP3" / "A.mp3").write_bytes(b"sibling")
        initial = self.invoke()
        self.assertEqual(initial.returncode, 0, initial.stderr)
        manifest = json.loads(initial.stdout)["manifest"]
        asserted = self.root.parent / "asserted-dfs.json"
        asserted.write_text(json.dumps(manifest), encoding="utf-8")
        result = self.invoke("--asserted", str(asserted))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)["receipt"]["asserted_match"])

    def test_playlist_reference_preserves_significant_trailing_whitespace(self) -> None:
        (self.root / "MP3" / "A" / "song.mp3 ").write_bytes(b"space")
        (self.root / "Playlists" / "mix.m3u").write_bytes(b"MP3/A/song.mp3 \n")
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = {row["path"]: row for row in json.loads(result.stdout)["manifest"]["items"]}
        self.assertEqual(rows["Playlists/mix.m3u"]["references"], ["MP3/A/song.mp3 "])

    def test_global_manifest_independently_hashes_files_and_attests_assertions(self) -> None:
        import hashlib

        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        manifest = output["manifest"]
        self.assertEqual((manifest["role"], manifest["epoch"]), ("source", "E0"))
        self.assertEqual(len(manifest["items"]), 6)
        by_path = {row["path"]: row for row in manifest["items"]}
        self.assertEqual(len(by_path), 6)
        self.assertEqual(by_path["MP3/A/song.mp3"]["sha256"], hashlib.sha256(b"abc").hexdigest())
        self.assertEqual(by_path["MP3/A/song.mp3"]["size"], 3)
        self.assertEqual(by_path["Playlists/mix.m3u"]["references"], ["MP3/A/song.mp3"])
        self.assertEqual(output["receipt"]["status"], "closed_local_census")
        self.assertEqual(output["receipt"]["hashed_files"], 3)
        self.assertEqual(output["receipt"]["rows"], 6)
        self.assertEqual(output["receipt"]["coverage"], "local_observation_only")
        self.assertNotIn(str(self.root), result.stdout)
        asserted = self.root.parent / "asserted.json"
        asserted.write_text(json.dumps({**manifest, "items": list(reversed(manifest["items"]))}), encoding="utf-8")
        matched = self.invoke("--asserted", str(asserted))
        self.assertEqual(matched.returncode, 0, matched.stderr)
        self.assertEqual(json.loads(matched.stdout)["receipt"]["asserted_match"], True)
        # A misleading assertion can never be promoted into a passing receipt.
        document = json.loads(asserted.read_text(encoding="utf-8"))
        document["items"] = document["items"][:-1]
        asserted.write_text(json.dumps(document), encoding="utf-8")
        mismatch = self.invoke("--asserted", str(asserted))
        self.assertEqual(mismatch.returncode, 1)
        self.assertEqual(mismatch.stdout, "")

    def test_global_namespace_catches_case_unicode_and_ancestry_collisions(self) -> None:
        for first, second in (("Song.mp3", "song.mp3"), ("Café.mp3", "Café.mp3")):
            with self.subTest(first=first):
                root = self.root / "MP3" / "A"
                (root / first).write_bytes(b"1")
                (root / second).write_bytes(b"2")
                # Some filesystems normalize or fold names; skip only when they alias.
                if len({entry.name for entry in root.iterdir() if entry.name in (first, second)}) == 2:
                    self.assertEqual(self.invoke().returncode, 1)
                (root / first).unlink(missing_ok=True)
                (root / second).unlink(missing_ok=True)

    def test_symlink_root_ancestor_and_child_fail_without_following(self) -> None:
        outside = self.root.parent / "outside"
        outside.mkdir()
        (outside / "track.mp3").write_bytes(b"outside")
        (self.root / "MP3" / "A" / "link.mp3").symlink_to(outside / "track.mp3")
        self.assertEqual(self.invoke().returncode, 1)
        (self.root / "MP3" / "A" / "link.mp3").unlink()
        alias = self.root.parent / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        self.assertEqual(self.invoke("--root", str(alias)).returncode, 1)
        ancestor = self.root.parent / "ancestor"
        ancestor.symlink_to(self.root.parent, target_is_directory=True)
        self.assertEqual(self.invoke("--root", str(ancestor / "library")).returncode, 1)

    def test_cloud_placeholder_read_error_and_volume_changes_fail_closed(self) -> None:
        collector = load_collector()
        (self.root / "MP3" / "A" / "sparse.mp3").write_bytes(b"x")
        with (self.root / "MP3" / "A" / "sparse.mp3").open("r+b") as handle:
            handle.truncate(1_000_000)
        # Explicit placeholder metadata can be emulated without cloud services.
        original = collector.is_placeholder
        with mock.patch.object(collector, "is_placeholder", side_effect=lambda st: st.st_size == 1_000_000 or original(st)):
            with self.assertRaises(collector.CensusError):
                collector.collect(self.root, "source", "E0")
        (self.root / "MP3" / "A" / "sparse.mp3").unlink()
        with mock.patch.object(collector, "scan_names", side_effect=OSError("synthetic read failure")):
            with self.assertRaises(collector.CensusError):
                collector.collect(self.root, "source", "E0")
        with mock.patch.object(collector, "same_volume", return_value=False):
            with self.assertRaises(collector.CensusError):
                collector.collect(self.root, "source", "E0")

    def test_incomplete_traversal_and_source_drift_fail_closed(self) -> None:
        collector = load_collector()
        scan = collector.scan_names
        with mock.patch.object(collector, "scan_names", side_effect=lambda fd: scan(fd)[:-1]):
            with self.assertRaises(collector.CensusError):
                collector.collect(self.root, "source", "E0")
        walk = collector.walk
        calls = 0

        def drift(*args, **kwargs):
            nonlocal calls
            result = walk(*args, **kwargs)
            calls += 1
            if calls == 1:
                (self.root / "MP3" / "A" / "late.mp3").write_bytes(b"late")
            return result

        with mock.patch.object(collector, "walk", side_effect=drift):
            with self.assertRaises(collector.CensusError):
                collector.collect(self.root, "source", "E0")
        (self.root / "MP3" / "A" / "late.mp3").unlink()

        def mutate(*args, **kwargs):
            nonlocal calls
            result = walk(*args, **kwargs)
            calls += 1
            if calls % 2 == 1:
                (self.root / "MP3" / "A" / "song.mp3").write_bytes(b"changed")
            return result

        with mock.patch.object(collector, "walk", side_effect=mutate):
            with self.assertRaises(collector.CensusError):
                collector.collect(self.root, "source", "E0")

    def test_nested_symlink_swap_after_second_walk_fails_closed(self) -> None:
        collector = load_collector()
        walk = collector.walk
        calls = 0

        def swap_nested(*args, **kwargs):
            nonlocal calls
            result = walk(*args, **kwargs)
            calls += 1
            if calls == 2:
                parent = self.root / "MP3"
                (parent / "A").rename(parent / "A-old")
                (parent / "A").symlink_to(parent / "A-old", target_is_directory=True)
            return result

        with mock.patch.object(collector, "walk", side_effect=swap_nested):
            with self.assertRaises(collector.CensusError):
                collector.collect(self.root, "source", "E0")

    def test_aggregate_playlist_references_fail_during_first_walk(self) -> None:
        collector = load_collector()
        for index in range(3):
            (self.root / "Playlists" / f"{index:02}.m3u").write_text(
                "MP3/A/song.mp3\n", encoding="utf-8"
            )
        original = collector.references
        calls = []

        def counted(*args, **kwargs):
            calls.append(args)
            return original(*args, **kwargs)

        with mock.patch.object(collector.policy, "MAX_REFERENCES", 1), \
             mock.patch.object(collector, "references", side_effect=counted):
            with self.assertRaises(collector.CensusError):
                collector.collect(self.root, "source", "E0")
        self.assertEqual(len(calls), 2)

    def test_replaced_root_path_cannot_attest_stale_directory_fd(self) -> None:
        collector = load_collector()
        walk = collector.walk
        calls = 0

        def replace_root(*args, **kwargs):
            nonlocal calls
            result = walk(*args, **kwargs)
            calls += 1
            if calls == 1:
                self.root.rename(self.root.parent / "old-library")
                self.root.mkdir()
            return result

        with mock.patch.object(collector, "walk", side_effect=replace_root):
            with self.assertRaises(collector.CensusError):
                collector.collect(self.root, "source", "E0")

    def test_provisional_scale_closes_one_global_manifest(self) -> None:
        for index in range(7_357):
            (self.root / "MP3" / "A" / f"{index:05}.mp3").write_bytes(b"x")
        for index in range(350):
            (self.root / "MP3" / "A" / f"{index:05}.lrc").write_bytes(b"line")
        collector = load_collector()
        started = time.monotonic()
        result = collector.collect(self.root, "source", "E0")
        elapsed = time.monotonic() - started
        self.assertEqual(result["receipt"]["rows"], 7_713)
        self.assertEqual(result["receipt"]["hashed_files"], 7_710)
        self.assertEqual(len({row["path"] for row in result["manifest"]["items"]}), 7_713)
        self.assertLess(elapsed, 60, f"synthetic 7,358-track census took {elapsed:.2f}s")

    def test_internal_parent_playlist_reference_and_item_limit(self) -> None:
        playlist = self.root / "Playlists" / "mix.m3u"
        playlist.write_text("../MP3/A/song.mp3\n", encoding="utf-8")
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        row = next(row for row in json.loads(result.stdout)["manifest"]["items"] if row["path"] == "Playlists/mix.m3u")
        self.assertEqual(row["references"], ["MP3/A/song.mp3"])
        playlist.write_text("MP3/A/song.mp3\n", encoding="utf-8")
        collector = load_collector()
        with mock.patch.object(collector.policy, "MAX_ITEMS", 5):
            with self.assertRaises(collector.CensusError):
                collector.collect(self.root, "source", "E0")

    def test_album_root_windows_absolute_and_repeated_references_preserve_bytes(self) -> None:
        import hashlib

        playlist = self.root / "MP3/A/album.m3u"
        body = ("#EXTM3U\nsong.mp3\nsong.mp3\nMP3\\A\\song.mp3\n" + str(self.root / "MP3/A/song.mp3") + "\n").encode()
        playlist.write_bytes(body)
        literal = "MP3/A/" + chr(0x200B) + "original.mp3"
        (self.root / literal).write_bytes(b"literal unicode original")
        collector = load_collector()
        envelope = collector.collect(self.root, "source", "E0")
        rows = {row["path"]: row for row in envelope["manifest"]["items"]}
        self.assertEqual(rows["MP3/A/album.m3u"]["references"], ["MP3/A/song.mp3"] * 4)
        self.assertEqual(rows["MP3/A/album.m3u"]["sha256"], hashlib.sha256(body).hexdigest())
        self.assertEqual(playlist.read_bytes(), body)
        self.assertIn(literal, rows)
        labels = {row["path"]: row for row in collector.policy.classify(envelope["manifest"]["items"])["items"]}
        self.assertEqual(labels["MP3/A/album.m3u"]["disposition"], "playlist")
        self.assertEqual(labels[literal]["disposition"], "eligible_original")

    def test_unusable_or_ambiguous_playlists_are_hashed_and_retained(self) -> None:
        import hashlib

        collector = load_collector()
        bodies = {"outside.m3u": b"../../outside.mp3\n", "encoding.m3u": b"\xff\xfe\x00bad", "ambiguous.m3u": b"song.mp3\n"}
        (self.root / "song.mp3").write_bytes(b"other literal file")
        for name, body in bodies.items():
            (self.root / "MP3/A" / name).write_bytes(body)
        envelope = collector.collect(self.root, "source", "E0")
        rows = {row["path"]: row for row in envelope["manifest"]["items"]}
        labels = {row["path"]: row for row in collector.policy.classify(envelope["manifest"]["items"])["items"]}
        for name, body in bodies.items():
            path = "MP3/A/" + name
            self.assertNotIn("references", rows[path])
            self.assertEqual(rows[path]["sha256"], hashlib.sha256(body).hexdigest())
            self.assertEqual(labels[path]["disposition"], "retained_companion")
            self.assertEqual(labels[path]["served"], "exclude")


if __name__ == "__main__":
    unittest.main()
