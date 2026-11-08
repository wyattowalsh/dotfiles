"""Synthetic, offline contract tests for the provisional ST01 manifest policy."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("mba-media-policy.py")


def file(path: str, **overrides: object) -> dict[str, object]:
    item: dict[str, object] = {
        "path": path,
        "kind": "file",
        "readable": True,
        "local": True,
    }
    item.update(overrides)
    return item


class MediaPolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="synthetic-media-policy-")
        self.addCleanup(temporary.cleanup)
        self.input = Path(temporary.name) / "manifest.json"

    def invoke(self, value: object) -> subprocess.CompletedProcess[str]:
        self.input.write_text(json.dumps(value), encoding="utf-8")
        return self.run_cli(str(self.input))

    def run_cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "-I", str(SCRIPT), "--input", *args],
            capture_output=True,
            text=True,
            timeout=10,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            check=False,
        )

    def classify(self, *items: dict[str, object]) -> list[dict[str, object]]:
        paths = {item["path"] for item in items}
        ancestors: set[str] = set()
        for path in paths:
            parts = path.split("/")
            if path.startswith("/") or any(part in ("", ".", "..") for part in parts):
                continue
            ancestors.update("/".join(parts[:index]) for index in range(1, len(parts)))
        parents = [file(path, kind="directory") for path in sorted(ancestors - paths)]
        result = self.invoke({"schema_version": 1, "items": parents + list(items)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        output = json.loads(result.stdout)
        self.assertEqual(output["policy_version"], "st01-v2-originals")
        self.assertEqual(output["coverage"], "unverified")
        self.assertIn("user-approved policy", output["limitation"])
        self.assertIn("current source census", output["limitation"])
        return output["items"][len(parents) :]

    def test_mp3_and_flac_are_distinct_served_and_phone_originals(self) -> None:
        rows = self.classify(
            file("MP3/Artist/Album/song.mp3"), file("FLAC/Artist/Album/song.flac")
        )
        self.assertEqual(
            [row["path"] for row in rows],
            ["MP3/Artist/Album/song.mp3", "FLAC/Artist/Album/song.flac"],
        )
        for row in rows:
            self.assertEqual(row["disposition"], "eligible_original")
            self.assertEqual(
                (row["served"], row["phone"], row["retained"]),
                ("include", "include", "include"),
            )
            self.assertEqual(row["reasons"], [])

    def test_existing_ingest_originals_and_non_audio_retention_are_distinct(self) -> None:
        rows = self.classify(
            file("Wave/A/song.wav"), file("MP3/A/song.opus"), file("other.txt")
        )
        for row in rows[:2]:
            self.assertEqual((row["served"], row["phone"]), ("include", "include"))
        self.assertEqual(rows[2]["disposition"], "retained_companion")
        self.assertEqual((rows[2]["served"], rows[2]["phone"]), ("exclude", "exclude"))
        for row in rows:
            self.assertEqual(row["retained"], "include")

    def test_measured_roots_original_formats_album_playlist_and_companions(self) -> None:
        rows = self.classify(file("Wave/A/original.wav"), file("AIFF/A/original.aif"),
            file("AAC/A/original.m4a"), file("AAC/A/album.m3u", references=["AAC/A/original.m4a"] * 2),
            file("AAC/A/movie.mov"), file("AAC/A/album.cue"), file("AAC/A/album.nfo"),
            file("AAC/A/album.sfv"), file("AAC/A/notes.txt"), file("root-notes"))
        self.assertTrue(all(row["disposition"] == "eligible_original" for row in rows[:3]))
        self.assertEqual(rows[3]["disposition"], "playlist")
        for row in rows[4:]:
            self.assertEqual((row["disposition"], row["served"], row["phone"], row["retained"]),
                ("retained_companion", "exclude", "exclude", "include"))

    def test_actual_lowercase_wave_and_wav_roots_keep_literal_original_paths(self) -> None:
        paths = ["wave/A/original.wav", "WAV/B/original.wav", "aiff/C/original.aif", "aac/D/original.m4a"]
        rows = self.classify(*(file(path) for path in paths))
        self.assertEqual([row["path"] for row in rows], paths)
        self.assertTrue(all(row["disposition"] == "eligible_original" for row in rows))

    def test_explicit_transient_paths_are_excluded_without_delete_authority(
        self,
    ) -> None:
        rows = self.classify(
            file("Incoming/review/dupe.flac"),
            file("Incoming/staging/a.mp3"),
            file("Incoming/quarantine/a.flac"),
            file("MP3/A/a.partial"),
            file("MP3/A/._a.mp3"),
            file("MP3/A/.DS_Store"),
            file("MP3/A/library.db"),
            file("MP3/.Trashes/song.mp3"),
            file("Incoming/downloading/song.flac"),
        )
        for row in rows:
            self.assertEqual(row["disposition"], "excluded_transient")
            self.assertEqual((row["served"], row["phone"]), ("exclude", "exclude"))
            self.assertEqual(
                row["retained"],
                "include" if row["path"].startswith("Incoming/") else "exclude",
            )
            self.assertIn("explicit_transient", row["reasons"])

    def test_review_audio_is_retained_even_when_not_served_or_sent(self) -> None:
        row = self.classify(file("Incoming/review/unmatched.mp3"))[0]
        self.assertEqual(
            (row["served"], row["phone"], row["retained"]),
            ("exclude", "exclude", "include"),
        )

    def test_original_formats_are_preserved_without_forcing_a_layout_rename(self) -> None:
        rows = self.classify(file("MP3/A/song.flac"), file("FLAC/A/song.mp3"))
        for row in rows:
            self.assertEqual(row["disposition"], "eligible_original")

    def test_incoming_other_is_unresolved_even_if_it_looks_like_mp3(self) -> None:
        rows = self.classify(
            file("Incoming/MP3/A/song.mp3"), file("Incoming/other/song.flac")
        )
        for row in rows:
            self.assertEqual(row["served"], "unresolved")
            self.assertEqual(row["phone"], "unresolved")
            self.assertIn("incoming_conflict", row["reasons"])

    def test_known_cover_is_served_only_with_track_in_same_directory(self) -> None:
        rows = self.classify(
            file("FLAC/A/Album/song.flac"), file("FLAC/A/Album/cover.jpg")
        )
        cover = rows[1]
        self.assertEqual(cover["disposition"], "intentional_sidecar")
        self.assertEqual(
            (cover["served"], cover["phone"], cover["retained"]),
            ("include", "exclude", "include"),
        )

    def test_sidecar_requires_an_associated_eligible_track(self) -> None:
        rows = self.classify(
            file("MP3/A/Album/cover.jpg"),
            file("MP3/A/Album/song.mp3"),
            file("MP3/A/Album/song.flac"),
            file("MP3/A/Album/song.lrc"),
            file("MP3/A/Album/other.txt"),
        )
        self.assertEqual(rows[0]["served"], "include")
        self.assertEqual(rows[2]["disposition"], "eligible_original")
        self.assertEqual(rows[3]["served"], "include")
        self.assertEqual(rows[4]["disposition"], "retained_companion")
        orphan = self.classify(file("FLAC/A/orphan/cover.jpg"))[0]
        self.assertIn("sidecar_without_track", orphan["reasons"])

    def test_multiple_cover_assets_are_preserved_without_arbitrary_selection(self) -> None:
        rows = self.classify(
            file("FLAC/A/Album/song.flac"),
            file("FLAC/A/Album/cover.jpg"),
            file("FLAC/A/Album/cover.png"),
        )
        for row in rows[1:]:
            self.assertEqual(row["disposition"], "intentional_sidecar")
            self.assertEqual(row["served"], "include")

    def test_distinct_cover_names_are_both_preserved(self) -> None:
        rows = self.classify(
            file("FLAC/A/Album/song.flac"),
            file("FLAC/A/Album/cover.jpg"),
            file("FLAC/A/Album/folder.jpg"),
        )
        for row in rows[1:]:
            self.assertEqual(row["disposition"], "intentional_sidecar")
            self.assertEqual(row["served"], "include")

    def test_playlist_references_must_be_explicit_safe_and_eligible(self) -> None:
        rows = self.classify(
            file("MP3/A/song.mp3"),
            file("Playlists/ok.m3u", references=["MP3/A/song.mp3"]),
            file("Playlists/unknown.m3u"),
            file("Playlists/escape.m3u", references=["../MP3/A/song.mp3"]),
            file("Playlists/missing.m3u", references=["MP3/A/missing.mp3"]),
        )
        self.assertEqual(
            (rows[1]["served"], rows[1]["phone"], rows[1]["retained"]),
            ("include", "exclude", "include"),
        )
        for row in rows[2:]:
            self.assertEqual(row["disposition"], "retained_companion")
            self.assertEqual(row["served"], "exclude")
            self.assertIn("playlist_references_unverified", row["reasons"])

    def test_symlink_unreadable_and_cloud_placeholder_override_other_classes(
        self,
    ) -> None:
        rows = self.classify(
            file("MP3/A/link.mp3", kind="symlink"),
            file("FLAC/A/locked.flac", readable=False),
            file("MP3/A/cloud.mp3", local=False),
            file("Incoming/review/link.mp3", kind="symlink"),
        )
        for row, reason in zip(
            rows, ("symlink", "unreadable", "cloud_placeholder", "symlink"), strict=True
        ):
            self.assertEqual(
                (row["served"], row["phone"], row["retained"]),
                ("unresolved", "unresolved", "unresolved"),
            )
            self.assertIn(reason, row["reasons"])

    def test_untrusted_parent_prevents_descendant_track_eligibility(self) -> None:
        rows = self.classify(
            file("MP3/A", kind="symlink"),
            file("MP3/A/song.mp3"),
            file("FLAC/B", kind="directory", local=False),
            file("FLAC/B/song.flac"),
        )
        self.assertIn("untrusted_ancestor", rows[1]["reasons"])
        self.assertIn("untrusted_ancestor", rows[3]["reasons"])
        self.assertEqual(rows[1]["phone"], "unresolved")
        self.assertEqual(rows[3]["phone"], "unresolved")

    def test_colliding_parent_directories_poison_descendants(self) -> None:
        rows = self.classify(
            file("MP3/A", kind="directory"),
            file("MP3/a", kind="directory"),
            file("MP3/A/song.mp3"),
        )
        self.assertIn("untrusted_ancestor", rows[2]["reasons"])

    def test_missing_ancestor_cannot_prove_eligible_media(self) -> None:
        result = self.invoke({"schema_version": 1, "items": [file("MP3/A/song.mp3")]})
        self.assertEqual(result.returncode, 0, result.stderr)
        row = json.loads(result.stdout)["items"][0]
        self.assertEqual(row["disposition"], "unresolved")
        self.assertIn("untrusted_ancestor", row["reasons"])

    def test_case_equivalent_symlink_ancestor_blocks_child(self) -> None:
        result = self.invoke(
            {
                "schema_version": 1,
                "items": [
                    file("MP3", kind="directory"),
                    file("MP3/A", kind="symlink"),
                    file("MP3/a/song.mp3"),
                ],
            }
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        row = json.loads(result.stdout)["items"][2]
        self.assertEqual(row["disposition"], "unresolved")
        self.assertIn("untrusted_ancestor", row["reasons"])

    def test_unsafe_lexical_alias_poisoning_ancestor(self) -> None:
        result = self.invoke(
            {
                "schema_version": 1,
                "items": [
                    file("MP3", kind="directory"),
                    file("./MP3", kind="symlink"),
                    file("MP3/A", kind="directory"),
                    file("MP3/A/song.mp3"),
                ],
            }
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = json.loads(result.stdout)["items"]
        self.assertEqual(rows[3]["disposition"], "unresolved")
        self.assertIn("untrusted_ancestor", rows[3]["reasons"])

    def test_unicode_format_filename_is_preserved_literally(self) -> None:
        path = "MP3/A/" + chr(0x202E) + "song.mp3"
        row = self.classify(file(path))[0]
        self.assertEqual(row["path"], path)
        self.assertEqual(row["disposition"], "eligible_original")

    def test_paths_outside_root_traversal_and_unsafe_names_are_unresolved(self) -> None:
        rows = self.classify(
            file("/tmp/song.mp3"),
            file("MP3/../FLAC/song.flac"),
            file("MP3//song.mp3"),
            file("MP3\\song.mp3"),
            file("MP3/A/\x00song.mp3"),
        )
        for row in rows:
            self.assertEqual(
                (row["served"], row["phone"]), ("unresolved", "unresolved")
            )
            self.assertIn("unsafe_path", row["reasons"])

    def test_case_and_unicode_collisions_poison_all_colliding_items(self) -> None:
        rows = self.classify(
            file("MP3/A/Song.mp3"),
            file("mp3/a/song.mp3"),
            file("FLAC/A/Café.flac"),
            file("FLAC/A/Café.flac"),
        )
        for row in rows:
            self.assertIn("path_collision", row["reasons"])
            self.assertEqual(
                (row["served"], row["phone"]), ("unresolved", "unresolved")
            )

    def test_duplicate_paths_are_not_silently_merged(self) -> None:
        rows = self.classify(file("MP3/A/a.mp3"), file("MP3/A/a.mp3"))
        for row in rows:
            self.assertIn("path_collision", row["reasons"])

    def test_no_implicit_input_and_bad_documents_fail_generically(self) -> None:
        result = subprocess.run(
            [sys.executable, "-I", str(SCRIPT)],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        self.assertEqual(result.returncode, 2)
        for bad in (
            {"schema_version": 1, "items": "wrong"},
            {"schema_version": True, "items": []},
            {"schema_version": 1, "items": [file("MP3/A/a.mp3", surprise=True)]},
            {
                "schema_version": 1,
                "items": [file("MP3/A/a.mp3", references=["MP3/A/a.mp3"])],
            },
        ):
            result = self.invoke(bad)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stdout, "")
            self.assertIn("invalid input", result.stderr)
            self.assertNotIn(str(self.input), result.stderr)

    def test_duplicate_json_keys_and_oversized_input_are_rejected(self) -> None:
        self.input.write_text(
            '{"schema_version":1,"schema_version":1,"items":[]}', encoding="utf-8"
        )
        self.assertEqual(self.run_cli(str(self.input)).returncode, 2)
        self.input.write_text("x" * 24_000_001, encoding="utf-8")
        self.assertEqual(self.run_cli(str(self.input)).returncode, 2)

    def test_whole_envelope_7358_tracks_plus_dirs_sidecars_and_refs(self) -> None:
        album = "MP3/Artist/" + "Album-" + "x" * 80
        tracks = [file(f"{album}/{index:05}.mp3") for index in range(7_358)]
        sidecars = [file(f"{album}/{index:05}.lrc") for index in range(350)]
        refs = [track["path"] for track in tracks[:1_500]]
        items = [file("MP3", kind="directory"), file("MP3/Artist", kind="directory"),
                 file(album, kind="directory"), file("Playlists", kind="directory"),
                 *tracks, *sidecars,
                 file("Playlists/list.m3u", references=refs)]
        payload = json.dumps({"schema_version": 1, "items": items}).encode()
        self.assertGreater(len(payload), 1_000_000)
        self.assertLess(len(payload), 24_000_000)
        self.assertLess(len(items), 10_000)
        result = self.invoke({"schema_version": 1, "items": items})
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = json.loads(result.stdout)["items"]
        self.assertEqual(sum(row["disposition"] == "eligible_original" for row in rows), 7_358)
        self.assertEqual(sum(row["disposition"] == "intentional_sidecar" for row in rows), 350)
        self.assertEqual(rows[-1]["disposition"], "playlist")

    def test_global_row_and_reference_limits_fail_closed(self) -> None:
        many = [file(f"MP3/{index:05}.mp3") for index in range(10_001)]
        self.assertEqual(self.invoke({"schema_version": 1, "items": many}).returncode, 2)
        refs = [f"MP3/A/{index:05}.mp3" for index in range(20_001)]
        allowed = self.invoke({"schema_version": 1, "items": [
            file("Playlists", kind="directory"),
            file("Playlists/one.m3u", references=refs[:-1]),
        ]})
        self.assertEqual(allowed.returncode, 0, allowed.stderr)
        rejected = self.invoke({"schema_version": 1, "items": [
            file("Playlists/one.m3u", references=refs[:10_001]),
            file("Playlists/two.m3u", references=refs[10_001:]),
        ]})
        self.assertEqual(rejected.returncode, 2)

    def test_global_collision_poisons_distant_track_and_playlist_reference(self) -> None:
        tracks = [file(f"MP3/A/{index:05}.mp3") for index in range(3_000)]
        items = [file("MP3", kind="directory"), file("MP3/A", kind="directory"),
                 file("Playlists", kind="directory"), *tracks,
                 file("mp3/a/00000.mp3"),
                 file("Playlists/mix.m3u", references=["MP3/A/00000.mp3"])]
        result = self.invoke({"schema_version": 1, "items": items})
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = json.loads(result.stdout)["items"]
        self.assertIn("path_collision", rows[3]["reasons"])
        self.assertIn("path_collision", rows[-2]["reasons"])
        self.assertIn("playlist_references_unverified", rows[-1]["reasons"])

    def compare_manifests(
        self,
        source: list[dict[str, object]],
        shadow: list[dict[str, object]],
        *,
        source_epoch: str = "E0",
        shadow_epoch: str = "E0",
    ) -> tuple[subprocess.CompletedProcess[str], dict[str, object] | None]:
        destination = self.input.with_name("shadow.json")

        def with_ancestors(items: list[dict[str, object]]) -> list[dict[str, object]]:
            ancestors = {
                "/".join(parts[:index])
                for item in items
                for parts in [item["path"].split("/")]
                for index in range(1, len(parts))
            }
            return [file(path, kind="directory") for path in sorted(ancestors)] + items

        self.input.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "epoch": source_epoch,
                    "role": "source",
                    "items": with_ancestors(source),
                }
            ),
            encoding="utf-8",
        )
        destination.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "epoch": shadow_epoch,
                    "role": "shadow",
                    "items": with_ancestors(shadow),
                }
            ),
            encoding="utf-8",
        )
        result = self.run_cli(str(self.input), "--compare", str(destination))
        return result, json.loads(result.stdout) if result.stdout else None

    def test_matching_e0_and_e1_compare_full_originals_and_served_sidecars(self) -> None:
        items = [
            file("MP3/A/song.mp3", size=3, sha256="a" * 64),
            file("FLAC/A/song.flac", size=11, sha256="b" * 64),
            file("FLAC/A/cover.jpg", size=2, sha256="c" * 64),
            file("Playlists/list.m3u", size=1, sha256="d" * 64,
                 references=["MP3/A/song.mp3", "FLAC/A/song.flac"]),
            file("Incoming/review/dupe.mp3"),
        ]
        for epoch in ("E0", "E1"):
            with self.subTest(epoch=epoch):
                result, report = self.compare_manifests(items, items[:-1], source_epoch=epoch, shadow_epoch=epoch)
                self.assertEqual(result.returncode, 0, report)
                self.assertEqual(report["status"], "matching_assertions")
                self.assertEqual(report["epoch"], epoch)
                self.assertEqual(report["operation"], "compare_only")
                self.assertEqual(report["coverage"], "unverified")
                expected = {
                    "copied": {"count": 4, "bytes": 17},
                    "served": {"count": 4, "bytes": 17},
                    "phone": {
                        "count": 2,
                        "bytes": 14,
                        "paths": ["FLAC/A/song.flac", "MP3/A/song.mp3"],
                    },
                    "retained_sidecars": {
                        "count": 1,
                        "bytes": 2,
                        "paths": ["FLAC/A/cover.jpg"],
                    },
                    "retained_companions": {"count": 0, "bytes": 0, "paths": []},
                }
                self.assertEqual(report["source"], expected)
                self.assertEqual(report["shadow"], expected)
                self.assertEqual(report["missing_shadow"], [])
                self.assertEqual(report["extra_shadow"], [])
                self.assertNotIn("delete", result.stdout.lower())

    def test_playlist_references_are_compared_even_if_digest_assertions_match(self) -> None:
        tracks = [
            file("MP3/A/one.mp3", size=1, sha256="1" * 64),
            file("MP3/A/two.mp3", size=1, sha256="2" * 64),
        ]
        playlist = file("Playlists/mix.m3u", size=12, sha256="a" * 64,
                        references=["MP3/A/one.mp3"])
        changed_refs = file("Playlists/mix.m3u", size=12, sha256="a" * 64,
                            references=["MP3/A/two.mp3"])
        result, report = self.compare_manifests([*tracks, playlist], [*tracks, changed_refs])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(report["changed"], ["Playlists/mix.m3u"])
        self.assertEqual(report["coverage"], "unverified")

    def test_manifest_missing_extra_and_changed_paths_block_without_deleting(self) -> None:
        source = [
            file("MP3/A/song.mp3", size=3, sha256="a" * 64),
            file("FLAC/A/song.flac", size=11, sha256="b" * 64),
        ]
        shadow = [
            file("MP3/A/song.mp3", size=3, sha256="f" * 64),
            file("FLAC/A/extra.flac", size=11, sha256="b" * 64),
            file("Incoming/review/accidental.mp3"),
        ]
        result, report = self.compare_manifests(source, shadow)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["missing_shadow"], ["FLAC/A/song.flac"])
        self.assertEqual(report["extra_shadow"], ["FLAC/A/extra.flac", "Incoming/review/accidental.mp3"])
        self.assertEqual(report["changed"], ["MP3/A/song.mp3"])
        self.assertNotIn("delete", result.stdout.lower())

    def test_manifest_missing_digest_and_unknown_locality_block(self) -> None:
        source = [
            file("MP3/A/song.mp3", size=3),
            file("FLAC/A/other.flac", size=9, sha256="a" * 64, local=False),
        ]
        shadow = [file("MP3/A/song.mp3", size=3, sha256="a" * 64)]
        result, report = self.compare_manifests(source, shadow)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(report["missing_metadata"], ["MP3/A/song.mp3"])
        self.assertEqual(report["unresolved_source"], ["FLAC/A/other.flac"])
        self.assertEqual(report["source"]["served"], {"count": 1, "bytes": 3})
        self.assertEqual(
            report["source"]["phone"],
            {"count": 1, "bytes": 3, "paths": ["MP3/A/song.mp3"]},
        )
        shadow[0]["readable"] = False
        result, report = self.compare_manifests([file("MP3/A/song.mp3", size=3, sha256="a" * 64)], shadow)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(report["unresolved_shadow"], ["MP3/A/song.mp3"])

    def test_empty_manifests_do_not_pass_as_complete_library(self) -> None:
        result, report = self.compare_manifests([], [])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["blockers"], ["empty_source"])
        self.assertEqual(report["source"]["phone"], {"count": 0, "bytes": 0, "paths": []})

    def test_manifest_epoch_role_bounds_and_invalid_metadata_fail_closed(self) -> None:
        eligible = [file("MP3/A/song.mp3", size=3, sha256="a" * 64)]
        result, report = self.compare_manifests(eligible, eligible, shadow_epoch="E1")
        self.assertEqual((result.returncode, report), (2, None))
        self.assertEqual(result.stdout, "")
        for bad in (
            {"size": -1}, {"size": True}, {"size": 2**63},
            {"sha256": "not-a-digest"}, {"sha256": "A" * 64},
        ):
            with self.subTest(bad=bad):
                result, report = self.compare_manifests([file("MP3/A/song.mp3", **bad)], eligible)
                self.assertEqual((result.returncode, report), (2, None))
        result, report = self.compare_manifests([file("MP3/A", kind="directory", size=0)], eligible)
        self.assertEqual((result.returncode, report), (2, None))
        destination = self.input.with_name("shadow.json")
        document = json.loads(destination.read_text(encoding="utf-8"))
        document["role"] = "source"
        destination.write_text(json.dumps(document), encoding="utf-8")
        result = self.run_cli(str(self.input), "--compare", str(destination))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
