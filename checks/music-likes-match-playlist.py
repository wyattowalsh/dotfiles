#!/usr/bin/env -S uv run python
"""Offline playlist safety regressions using a synthetic HOME and SQLite library."""
from __future__ import annotations

import csv
import hashlib
import importlib.util
import json
import os
import sqlite3
import stat
import struct
import sys
import tempfile
import unittest
from contextlib import closing
from importlib.machinery import SourceFileLoader
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "rig/home/dot_local/bin/executable_music-likes-match"
LOADER = SourceFileLoader("music_likes_match_playlist", str(SCRIPT))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC is not None
module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = module
LOADER.exec_module(module)


class PlaylistSafetyTests(unittest.TestCase):
    def setUp(self) -> None:
        sandbox = tempfile.TemporaryDirectory(prefix="music-likes-playlist-test-")
        self.addCleanup(sandbox.cleanup)
        self.home = Path(sandbox.name)
        self.state = self.home / ".local/share/music-likes"
        self.state.mkdir(parents=True)
        self.library = self.home / "Music/Library"
        self.playlist = self.library / "Playlists/Liked Songs.m3u"
        env = patch.dict(os.environ, {
            "HOME": str(self.home),
            module.STATE_ENV: str(self.state),
            module.FIXTURE_ENV: "",
        })
        env.start()
        self.addCleanup(env.stop)
        self._liked()
        db_path = self.home / ".local/share/beets/library.db"
        db_path.parent.mkdir(parents=True)
        with closing(sqlite3.connect(db_path)) as conn:
            conn.executescript("""
                CREATE TABLE items (
                    id INTEGER PRIMARY KEY, path TEXT, title TEXT, artist TEXT,
                    albumartist TEXT, album TEXT, isrc TEXT, mb_trackid TEXT,
                    length REAL, format TEXT, subtitle TEXT, bitrate INTEGER
                );
                CREATE TABLE item_attributes (entity_id INTEGER, key TEXT, value TEXT);
            """)
            conn.executemany(
                "INSERT INTO items VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    (1, "FLAC/Artist/Song.flac", "Song", "Artist", "Artist", "Album",
                     "", "", 180.0, "FLAC", None, 0),
                    (2, "MP3/Artist/Song.mp3", "Song", "Artist", "Artist", "Album",
                     "", "", 180.0, "MP3", None, 320000),
                ],
            )
            conn.commit()

    def _liked(self) -> None:
        with (self.state / module.LIKED_NAME).open("w", newline="", encoding="utf-8") as fh:
            writer = csv.DictWriter(fh, fieldnames=module.EXPORTIFY_COLUMNS)
            writer.writeheader()
            writer.writerow({
                "Track URI": "spotify:track:synthetic",
                "Track Name": "Song",
                "Artist Name(s)": "Artist",
                "Album Name": "Album",
                "Album Artist Name(s)": "Artist",
                "Track Duration (ms)": "180000",
            })

    def _audio(self, relative: str) -> None:
        path = self.library / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        frame = b"\xff\xfb\xe0\x00" + bytes(1040)
        path.write_bytes(b"fLaC" + bytes(38) if path.suffix == ".flac" else frame * 2)

    def _library_mode(self, ids: tuple[int, ...] = (2,), title: str = "Song (Original Mix)") -> None:
        (self.state / module.LIKED_NAME).unlink()
        os.environ[module.LIBRARY_ENV] = str(self.library.resolve())
        os.environ[module.BEETS_ENV] = str((self.home / ".local/share/beets/library.db").resolve())
        with closing(sqlite3.connect(module.beets_db_path())) as conn:
            for column in ("mb_albumid", "mb_releasetrackid", "catalognum", "disc", "track"):
                conn.execute(f"ALTER TABLE items ADD COLUMN {column} TEXT")
            conn.execute("UPDATE items SET title=?, mb_albumid='00000000-0000-4000-8000-000000000001', mb_releasetrackid='00000000-0000-4000-8000-000000001001', catalognum='CAT1', disc='1', track='1'", (title,))
            conn.execute("DELETE FROM items WHERE id NOT IN (" + ",".join("?" for _ in ids) + ")", ids)
            paths = conn.execute("SELECT path FROM items").fetchall()
            conn.commit()
        for (path,) in paths:
            self._audio(path)

    def _library_rows(self) -> list[dict[str, str]]:
        with (self.state / module.MISSING_NAME).open(newline="", encoding="utf-8") as handle:
            return [row for row in csv.DictReader(handle) if row["Origin"] == "library"]

    def test_library_mode_requires_explicit_source_without_replacing_queue(self) -> None:
        sentinel = self.state / module.MISSING_NAME
        sentinel.write_text("retain queue\n")
        with patch.dict(os.environ, {module.LIBRARY_ENV: "", module.BEETS_ENV: ""}), self.assertRaises(SystemExit):
            module.cmd_match(apply=True, force=False, include_library=True)
        self.assertEqual(sentinel.read_text(), "retain queue\n")

    def test_library_mp3_gap_without_spotify_keeps_current_evidence_and_ignores_title_index(self) -> None:
        self._library_mode()
        (self.state / "index-flac.csv").write_text("Song\n")
        with patch.object(module, "index_has", side_effect=AssertionError("title index used")):
            module.cmd_match(apply=True, force=False, include_library=True)
        rows = self._library_rows()
        self.assertEqual([(row["Format"], row["IdentityStatus"]) for row in rows], [("flac", "source-anchored")])
        evidence = json.loads(rows[0]["SourceEvidence"])
        source = self.library / "MP3/Artist/Song.mp3"
        self.assertEqual(evidence["members"][0]["sha256"], hashlib.sha256(source.read_bytes()).hexdigest())
        self.assertEqual(evidence["members"][0]["path"], "MP3/Artist/Song.mp3")
        self.assertEqual(evidence["metadata"]["release_id"], "00000000-0000-4000-8000-000000000001")
        state = module.read_json(self.state / module.STATE_NAME)
        entry = next(value for key, value in state.items() if key.startswith("library:"))
        self.assertEqual(entry["source_evidence"], evidence)
        self.assertEqual(entry["missing_formats"], ["flac"])
        module.cmd_match(apply=True, force=False, include_library=True)
        self.assertEqual(self._library_rows(), [])

    def test_library_lossless_and_exact320_are_independent(self) -> None:
        self._library_mode((1,))
        module.cmd_match(apply=True, force=False, include_library=True)
        self.assertEqual([row["Format"] for row in self._library_rows()], ["mp3-320"])

    def test_library_known_release_format_pair_is_complete(self) -> None:
        self._library_mode((1, 2))
        module.cmd_match(apply=True, force=False, include_library=True)
        self.assertEqual(self._library_rows(), [])

    def test_library_malformed_id_cannot_supply_a_positive_items_counterpart(self) -> None:
        self._library_mode((1, 2))
        with closing(sqlite3.connect(module.beets_db_path())) as conn:
            conn.execute("UPDATE items SET id=0 WHERE id=1")
            conn.commit()
        module.cmd_match(apply=True, force=False, include_library=True)
        rows = self._library_rows()
        self.assertEqual([row["Format"] for row in rows if row["BeetsItemId"] == "2"], ["flac"])
        malformed = [row for row in rows if not row["BeetsItemId"]]
        self.assertEqual(len(malformed), 2)
        self.assertTrue(all(row["IdentityStatus"] == "unresolved" and row["Reason"] == "unknown_or_ambiguous_item_id" for row in malformed))

    def test_library_distinct_releases_never_complete_each_other(self) -> None:
        self._library_mode((1, 2))
        with closing(sqlite3.connect(module.beets_db_path())) as conn:
            conn.execute("UPDATE items SET mb_albumid='00000000-0000-4000-8000-000000000002',mb_releasetrackid='00000000-0000-4000-8000-000000001002' WHERE id=2")
            conn.commit()
        module.cmd_match(apply=True, force=False, include_library=True)
        self.assertEqual([(row["BeetsItemId"], row["Format"]) for row in self._library_rows()], [("1", "mp3-320"), ("2", "flac")])

    def test_library_conflicting_durations_under_one_release_track_are_held(self) -> None:
        self._library_mode((1, 2))
        with closing(sqlite3.connect(module.beets_db_path())) as conn:
            conn.execute("UPDATE items SET length=184 WHERE id=2")
            conn.commit()
        module.cmd_match(apply=True, force=False, include_library=True)
        self.assertEqual([(row["BeetsItemId"], row["Format"]) for row in self._library_rows()], [("1", "mp3-320"), ("2", "flac")])
        self.assertTrue(all(row["Reason"] == "duration_identity_conflict" for row in self._library_rows()))

    def test_library_like_thiz_unclassified_is_actionable_but_unknown_release_is_held(self) -> None:
        self._library_mode(title="Like Thiz")
        with closing(sqlite3.connect(module.beets_db_path())) as conn:
            conn.execute("UPDATE items SET artist='Josh & Wesz', albumartist='Various Artists', album='Goodgreef Xtra Hard', length=402.05061224489793, catalognum='NEWCD0951', mb_albumid='ef4910a4-989a-4666-b1b9-d46632733705', mb_releasetrackid='599b5ed5-2f95-4cbe-ac7d-daa2b6c75dd6', mb_trackid='7484cdd7-dd34-48ae-ae8f-d8e469387536'")
            conn.commit()
        module.cmd_match(apply=True, force=True, include_library=True)
        row = self._library_rows()[0]
        self.assertEqual((row["Title"], row["Version"], row["IdentityStatus"], row["Reason"]),
                         ("Like Thiz", "unclassified", "source-anchored", ""))
        self.assertEqual((row["Artist"], row["Album"], row["Format"], row["Length"]),
                         ("Josh & Wesz", "Goodgreef Xtra Hard", "flac",  "402"))
        self.assertEqual(json.loads(row["SourceEvidence"])["metadata"]["catalog_number"], "NEWCD0951")
        with closing(sqlite3.connect(module.beets_db_path())) as conn:
            conn.execute("UPDATE items SET title='Song (Radio Edit)', mb_albumid='' ")
            conn.commit()
        module.cmd_match(apply=True, force=True, include_library=True)
        self.assertEqual(self._library_rows()[0]["Reason"], "release_identity_unresolved")

    def test_library_special_subtitle_is_preserved_and_never_reclassified(self) -> None:
        self._library_mode(title="Song")
        with closing(sqlite3.connect(module.beets_db_path())) as conn:
            conn.execute("UPDATE items SET subtitle='(Silver Nikan Remix)'")
            conn.commit()
        module.cmd_match(apply=True, force=False, include_library=True)
        row = self._library_rows()[0]
        metadata = json.loads(row["SourceEvidence"])["metadata"]
        self.assertEqual(metadata["subtitle"], "(Silver Nikan Remix)")
        self.assertEqual((row["Version"], row["IdentityStatus"]), ("unclassified", "source-anchored"))

    def test_library_source_alias_and_hardlink_are_unresolved(self) -> None:
        self._library_mode()
        path = self.library / "MP3/Artist/Song.mp3"
        target = self.library / "other.mp3"
        path.rename(target)
        path.symlink_to(target)
        item = module.load_library(module.beets_db_path())[0]
        self.assertIsNone(module.library_source_evidence(item))
        path.unlink()
        os.link(target, path)
        self.assertIsNone(module.library_source_evidence(item))

    def test_library_source_change_during_hash_is_unproved(self) -> None:
        self._library_mode()
        path = self.library / "MP3/Artist/Song.mp3"
        item = module.load_library(module.beets_db_path())[0]
        digest = hashlib.sha256()
        class RacingDigest:
            def update(self, chunk: bytes) -> None:
                digest.update(chunk)
                path.write_bytes(b"changed")
            def hexdigest(self) -> str:
                return digest.hexdigest()
        with patch.object(module.hashlib, "sha256", return_value=RacingDigest()):
            self.assertIsNone(module.library_source_evidence(item))

    def test_library_source_change_during_codec_read_never_completes_pair(self) -> None:
        self._library_mode()
        path = self.library / "MP3/Artist/Song.mp3"
        def changed(items: list[object]) -> list[str]:
            path.write_bytes(b"changed")
            return []
        with patch.object(module, "wanted_formats", side_effect=changed):
            module.cmd_match(apply=True, force=False, include_library=True)
        self.assertEqual([row["Format"] for row in self._library_rows()], ["flac", "mp3-320"])
        self.assertTrue(all(row["IdentityStatus"] == "unresolved" for row in self._library_rows()))

    def test_library_unrecognized_codec_keeps_both_gaps_unresolved(self) -> None:
        self._library_mode()
        (self.library / "MP3/Artist/Song.mp3").write_bytes(b"not an audio stream")
        module.cmd_match(apply=True, force=False, include_library=True)
        self.assertEqual([row["Format"] for row in self._library_rows()], ["flac", "mp3-320"])
        self.assertTrue(all(row["Reason"] == "codec_unproved" for row in self._library_rows()))

    def test_low_unknown_or_rounded_mp3_bitrate_does_not_satisfy_320(self) -> None:
        self._audio("MP3/Artist/Song.mp3")
        for bitrate in (160000, 192000, 319999, 0, None):
            with self.subTest(bitrate=bitrate):
                with closing(sqlite3.connect(self.home / ".local/share/beets/library.db")) as conn:
                    conn.execute("UPDATE items SET bitrate = ? WHERE id = 2", (bitrate,))
                    conn.commit()
                items = module.load_library(self.home / ".local/share/beets/library.db")
                self.assertEqual(module.wanted_formats(items), ["flac", "mp3-320"])

    def test_shared_isrc_cannot_complete_another_duration_editions_format_pair(self) -> None:
        self._audio("FLAC/Artist/Song.flac")
        self._audio("MP3/Artist/Song.mp3")
        with closing(sqlite3.connect(self.home / ".local/share/beets/library.db")) as conn:
            conn.execute("UPDATE items SET isrc='USABC0012345'")
            conn.execute("UPDATE items SET length=360 WHERE id=2")
            conn.commit()
        items = module.load_library(self.home / ".local/share/beets/library.db")
        liked = module.read_liked(self.state / module.LIKED_NAME)[0]
        liked.isrc_raw = "USABC0012345"
        for duration_ms, matched_length, missing in (
            (180000, 180.0, ["mp3-320"]),
            (360000, 360.0, ["flac"]),
        ):
            with self.subTest(duration_ms=duration_ms):
                liked.duration_ms = duration_ms
                matched, reason = module.match_result(liked, items)
                self.assertEqual(reason, "")
                self.assertEqual([item.length for item in matched], [matched_length])
                self.assertEqual(module.queue_formats(matched, reason), missing)

    def _companions(self) -> list[dict[str, str]]:
        fixture = SCRIPT.parents[4] / "checks/fixtures/music-likes/companion-editions.csv"
        with fixture.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        self._write_companions(rows)
        return rows

    def _write_companions(self, rows: list[dict[str, str]]) -> None:
        with (self.state / module.COMPANION_NAME).open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=module.COMPANION_HEADERS)
            writer.writeheader()
            writer.writerows(rows)

    def _companion_queue(self) -> list[dict[str, str]]:
        with (self.state / module.MISSING_NAME).open(newline="", encoding="utf-8") as handle:
            return [row for row in csv.DictReader(handle) if row["EditionId"]]

    def test_verified_companions_request_four_distinct_cells_without_changing_spotify(self) -> None:
        self._companions()
        liked_before = (self.state / module.LIKED_NAME).read_bytes()
        self.assertEqual(module.cmd_match(apply=True, force=False), 0)
        rows = self._companion_queue()
        self.assertEqual([(row["EditionId"], row["Format"], row["Length"]) for row in rows], [
            ("song-extended", "flac", "360"), ("song-extended", "mp3-320", "360"),
            ("song-radio", "flac", "195"), ("song-radio", "mp3-320", "195"),
        ])
        self.assertTrue(all(row["SpotifyId"] == "synthetic" and row["Evidence"] for row in rows))
        self.assertEqual((self.state / module.LIKED_NAME).read_bytes(), liked_before)
        report = module.read_json(self.state / module.COMPANION_REPORT_NAME)
        unresolved = [row for row in report["editions"] if row["state"] == "unresolved"]
        self.assertEqual(len(unresolved), 1)
        self.assertEqual(unresolved[0]["queued_formats"], [])
        self.assertEqual(unresolved[0]["declaration"]["Reason"], "Associated release not yet verified")
        self.assertEqual(stat.S_IMODE((self.state / module.COMPANION_REPORT_NAME).stat().st_mode), 0o600)

    def test_companion_presence_preserves_radio_and_remixer_identity_despite_shared_ids(self) -> None:
        self._companions()
        with closing(sqlite3.connect(self.home / ".local/share/beets/library.db")) as conn:
            conn.execute("UPDATE items SET title='Song (Radio Edit)', length=195, isrc='USABC0012345' WHERE id=2")
            conn.execute("UPDATE items SET title='Song (Other Remix) (Extended Mix)', length=360, isrc='USABC0012345' WHERE id=1")
            conn.commit()
        self._audio("MP3/Artist/Song.mp3")
        self._audio("FLAC/Artist/Song.flac")
        self.assertEqual(module.cmd_match(apply=True, force=False), 0)
        self.assertEqual([(row["EditionId"], row["Format"]) for row in self._companion_queue()], [
            ("song-extended", "flac"), ("song-extended", "mp3-320"), ("song-radio", "flac"),
        ])

    def test_companion_backoff_is_distinct_and_changed_target_resets_only_that_edition(self) -> None:
        rows = self._companions()
        with patch.object(module.time, "time", return_value=1000):
            module.cmd_match(apply=True, force=False)
            first = module.read_json(self.state / module.STATE_NAME)
            module.cmd_match(apply=True, force=False)
            self.assertEqual(self._companion_queue(), [])
            rows[0]["DurationMs"] = "420000"
            self._write_companions(rows)
            module.cmd_match(apply=True, force=False)
        self.assertEqual([(row["EditionId"], row["Length"]) for row in self._companion_queue()], [
            ("song-extended", "420"), ("song-extended", "420"),
        ])
        after = module.read_json(self.state / module.STATE_NAME)
        self.assertEqual(first["companion:song-radio"], after["companion:song-radio"])

    def test_invalid_companion_declarations_leave_existing_queue_unchanged(self) -> None:
        rows = self._companions()
        path = self.state / module.MISSING_NAME
        path.write_text("existing queue\n")
        for field, value in (("Evidence", ""), ("LikedTrackId", "not-liked"),
                             ("Version", "radio"), ("DurationMs", "0"), ("ISRC", "USABC0012345;garbage")):
            with self.subTest(field=field):
                invalid = [dict(rows[0])]
                invalid[0][field] = value
                self._write_companions(invalid)
                with self.assertRaises(SystemExit):
                    module.cmd_match(apply=True, force=False)
                self.assertEqual(path.read_text(), "existing queue\n")
        self._write_companions([rows[0], rows[0]])
        with self.assertRaises(SystemExit):
            module.cmd_match(apply=True, force=False)
        self.assertEqual(path.read_text(), "existing queue\n")

    def test_companion_preview_and_symlink_input_do_not_write_outputs(self) -> None:
        self._companions()
        module.cmd_match(apply=False, force=False)
        self.assertFalse((self.state / module.MISSING_NAME).exists())
        self.assertFalse((self.state / module.COMPANION_REPORT_NAME).exists())
        path = self.state / module.COMPANION_NAME
        outside = self.home / "declarations.csv"
        path.rename(outside)
        path.symlink_to(outside)
        with self.assertRaises(SystemExit):
            module.cmd_match(apply=True, force=False)
        self.assertFalse((self.state / module.MISSING_NAME).exists())

    def test_library_only_companions_validate_real_beets_parent_without_spotify_export(self) -> None:
        rows = self._companions()
        for row in rows:
            row.update({"LikedTrackId": "", "BeetsItemId": "2"})
        self._write_companions(rows)
        self._audio("MP3/Artist/Song.mp3")
        (self.state / module.LIKED_NAME).unlink()
        module.cmd_match(apply=True, force=False)
        queued = self._companion_queue()
        self.assertEqual(len(queued), 4)
        self.assertTrue(all(row["SpotifyId"] == "" and row["BeetsItemId"] == "2" for row in queued))
        self.assertFalse((self.state / module.LIKED_NAME).exists())
        original = (self.state / module.MISSING_NAME).read_bytes()
        for parent in ("999", "02", ""):
            with self.subTest(parent=parent):
                rows[0]["BeetsItemId"] = parent
                self._write_companions([rows[0]])
                with self.assertRaises(SystemExit):
                    module.cmd_match(apply=True, force=False)
                self.assertEqual((self.state / module.MISSING_NAME).read_bytes(), original)

    def test_library_companion_parent_requires_extant_in_library_file_and_one_parent_kind(self) -> None:
        rows = self._companions()
        rows[0].update({"LikedTrackId": "", "BeetsItemId": "2"})
        self._write_companions([rows[0]])
        with self.assertRaises(SystemExit):
            module.cmd_match(apply=True, force=False)
        self._audio("MP3/Artist/Song.mp3")
        rows[0]["LikedTrackId"] = "synthetic"
        self._write_companions([rows[0]])
        with self.assertRaises(SystemExit):
            module.cmd_match(apply=True, force=False)

    def test_exact320_db_value_needs_actual_matching_mpeg_headers(self) -> None:
        path = self.library / "MP3/Artist/Song.mp3"
        self._audio("MP3/Artist/Song.mp3")
        items = module.load_library(self.home / ".local/share/beets/library.db")
        self.assertEqual(items[1].bitrate, 320000)
        self.assertEqual(module.wanted_formats(items), ["flac"])
        for payload in (b"not mp3", (b"\xff\xfb\xb0\x00" + bytes(622)) * 2):
            path.write_bytes(payload)
            self.assertEqual(module.wanted_formats(items), ["flac", "mp3-320"])
        path.write_bytes((b"\xff\xfa\xe0\x00" + bytes(1040)) * 2)
        self.assertEqual(module.wanted_formats(items), ["flac"])

    def test_symlink_retarget_cannot_credit_outside_codec(self) -> None:
        self._audio("FLAC/Artist/Song.flac")
        inside = self.library / "FLAC/Artist/Song.flac"
        inside.write_bytes(b"not a FLAC codec")
        outside = self.home / "outside.flac"
        outside.write_bytes(b"fLaC" + bytes(38))
        link = inside.with_name("alias.flac")
        link.symlink_to(inside)
        item = module.load_library(self.home / ".local/share/beets/library.db")[0]
        item.path = "FLAC/Artist/alias.flac"
        original_resolve = Path.resolve
        canonical_link = link.parent.resolve() / link.name
        canonical_inside = inside.resolve()
        canonical_outside = outside.resolve()
        candidate_resolutions = []

        def retarget(path: Path, *args, **kwargs):
            result = original_resolve(path, *args, **kwargs)
            if path == canonical_link:
                candidate_resolutions.append(result)
                link.unlink()
                link.symlink_to(outside)
            return result

        with patch.object(Path, "resolve", retarget):
            self.assertEqual(module.owned_audio_formats(item), set())
        self.assertEqual(candidate_resolutions, [canonical_inside])
        self.assertEqual(link.resolve(), canonical_outside)

    def test_aifc_lossy_compression_is_not_lossless_presence(self) -> None:
        path = self.library / "AIFF/Artist/Song.aif"
        path.parent.mkdir(parents=True)
        with closing(sqlite3.connect(self.home / ".local/share/beets/library.db")) as conn:
            conn.execute("UPDATE items SET path = ?, format = 'AIFF' WHERE id = 1", ("AIFF/Artist/Song.aif",))
            conn.commit()
        item = module.load_library(self.home / ".local/share/beets/library.db")[0]
        for compression, expected in ((b"ulaw", set()), (b"NONE", {"flac"}), (b"sowt", {"flac"})):
            comm = bytes(18) + compression
            path.write_bytes(b"FORM" + struct.pack(">I", 4 + 8 + len(comm)) + b"AIFCCOMM" + struct.pack(">I", len(comm)) + comm)
            self.assertEqual(module.owned_audio_formats(item), expected)

    def test_wave_container_needs_lossless_codec_and_keeps_original_bytes(self) -> None:
        path = self.library / "WAVE/Artist/Song.wav"
        path.parent.mkdir(parents=True)
        with closing(sqlite3.connect(self.home / ".local/share/beets/library.db")) as conn:
            conn.execute("UPDATE items SET path = ?, format = 'WAVE' WHERE id = 1", ("WAVE/Artist/Song.wav",))
            conn.commit()
        item = module.load_library(self.home / ".local/share/beets/library.db")[0]
        for code, expected in ((6, set()), (1, {"flac"}), (3, {"flac"})):
            fmt = struct.pack("<HHIIHH", code, 2, 44100, 176400, 4, 16)
            payload = b"RIFF" + struct.pack("<I", 36) + b"WAVEfmt " + struct.pack("<I", 16) + fmt + b"data" + bytes(4)
            path.write_bytes(payload)
            before = path.stat()
            self.assertEqual(module.owned_audio_formats(item), expected)
            self.assertEqual(path.read_bytes(), payload)
            self.assertEqual((before.st_size, before.st_mtime_ns, before.st_ctime_ns),
                (path.stat().st_size, path.stat().st_mtime_ns, path.stat().st_ctime_ns))

    def _temp_files(self) -> list[Path]:
        return list(self.playlist.parent.glob(f".{self.playlist.name}.*.tmp"))

    def test_missing_flac_uses_real_mp3(self) -> None:
        self._audio("MP3/Artist/Song.mp3")
        self.assertEqual(module.cmd_playlist(apply=True), 0)
        text = self.playlist.read_text(encoding="utf-8")
        self.assertIn("../MP3/Artist/Song.mp3", text)
        self.assertNotIn("../FLAC/Artist/Song.flac", text)
        self.assertEqual(self._temp_files(), [])

    def test_stale_flac_db_row_queues_lossless_refetch_only(self) -> None:
        self._audio("MP3/Artist/Song.mp3")
        self.assertEqual(module.cmd_match(apply=True, force=False), 0)
        with (self.state / module.MISSING_NAME).open(newline="", encoding="utf-8") as fh:
            rows = list(csv.DictReader(fh))
        self.assertEqual([row["Format"] for row in rows], ["flac"])
        self.assertEqual(rows[0]["SpotifyId"], "synthetic")
        self.assertEqual(module.cmd_playlist(apply=True), 0)
        self.assertIn("../MP3/Artist/Song.mp3", self.playlist.read_text(encoding="utf-8"))

    def test_outside_library_paths_do_not_own_formats_or_enter_playlist(self) -> None:
        self._audio("MP3/Artist/Song.mp3")
        outside = self.home / "Music/outside.flac"
        outside.parent.mkdir(parents=True, exist_ok=True)
        outside.write_bytes(b"synthetic audio")
        linked = self.library / "FLAC/Artist/Song.flac"
        linked.parent.mkdir(parents=True, exist_ok=True)
        linked.symlink_to(outside)
        db_path = self.home / ".local/share/beets/library.db"
        for bad_path in ("../outside.flac", str(outside), "FLAC/Artist/Song.flac"):
            with self.subTest(path=bad_path):
                with closing(sqlite3.connect(db_path)) as conn:
                    conn.execute("UPDATE items SET path = ? WHERE id = 1", (bad_path,))
                    conn.commit()
                items = module.load_library(db_path)
                self.assertEqual(module.wanted_formats(items), ["flac"])
                self.assertEqual(module.cmd_playlist(apply=True), 0)
                text = self.playlist.read_text(encoding="utf-8")
                self.assertIn("../MP3/Artist/Song.mp3", text)
                self.assertNotIn("outside.flac", text)

    def test_both_files_choose_flac_and_preserve_existing_mode(self) -> None:
        self._audio("FLAC/Artist/Song.flac")
        self._audio("MP3/Artist/Song.mp3")
        self.playlist.parent.mkdir(parents=True)
        self.playlist.write_text("old playlist\n", encoding="utf-8")
        self.playlist.chmod(0o600)
        original_inode = self.playlist.stat().st_ino
        replace = os.replace

        def inspect_then_replace(src: str | os.PathLike[str], dst: str | os.PathLike[str]) -> None:
            self.assertEqual(self.playlist.read_text(encoding="utf-8"), "old playlist\n")
            self.assertIn("../FLAC/Artist/Song.flac", Path(src).read_text(encoding="utf-8"))
            replace(src, dst)

        with patch.object(module.os, "replace", side_effect=inspect_then_replace) as swapped:
            self.assertEqual(module.cmd_playlist(apply=True), 0)
        swapped.assert_called_once()
        self.assertIn("../FLAC/Artist/Song.flac", self.playlist.read_text(encoding="utf-8"))
        self.assertNotIn("../MP3/Artist/Song.mp3", self.playlist.read_text(encoding="utf-8"))
        self.assertNotEqual(self.playlist.stat().st_ino, original_inode)
        self.assertEqual(stat.S_IMODE(self.playlist.stat().st_mode), 0o600)
        self.assertEqual(self._temp_files(), [])

    def test_nonregular_flac_falls_back_to_mp3(self) -> None:
        (self.library / "FLAC/Artist/Song.flac").mkdir(parents=True)
        self._audio("MP3/Artist/Song.mp3")
        self.assertEqual(module.cmd_playlist(apply=True), 0)
        self.assertIn("../MP3/Artist/Song.mp3", self.playlist.read_text(encoding="utf-8"))

    def test_interrupted_publication_keeps_old_playlist_and_cleans_temp(self) -> None:
        self._audio("MP3/Artist/Song.mp3")
        self.playlist.parent.mkdir(parents=True)
        self.playlist.write_text("old playlist\n", encoding="utf-8")
        with patch.object(module.os, "replace", side_effect=OSError("interrupted")):
            with self.assertRaises(SystemExit):
                module.cmd_playlist(apply=True)
        self.assertEqual(self.playlist.read_text(encoding="utf-8"), "old playlist\n")
        self.assertEqual(self._temp_files(), [])

    def test_symlink_and_directory_targets_are_not_overwritten(self) -> None:
        self._audio("MP3/Artist/Song.mp3")
        self.playlist.parent.mkdir(parents=True)
        sentinel = self.home / "sentinel.txt"
        sentinel.write_text("leave me alone\n", encoding="utf-8")
        self.playlist.symlink_to(sentinel)
        with self.assertRaises(SystemExit):
            module.cmd_playlist(apply=True)
        self.assertTrue(self.playlist.is_symlink())
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "leave me alone\n")
        self.playlist.unlink()
        self.playlist.mkdir()
        with self.assertRaises(SystemExit):
            module.cmd_playlist(apply=True)
        self.assertTrue(self.playlist.is_dir())
        self.assertEqual(self._temp_files(), [])

    def test_new_target_appearing_before_replace_is_not_overwritten(self) -> None:
        self.playlist.parent.mkdir(parents=True)
        real_fsync = os.fsync

        def appear(fd: int) -> None:
            self.playlist.write_text("another writer\n", encoding="utf-8")
            real_fsync(fd)

        with patch.object(module.os, "fsync", side_effect=appear):
            with self.assertRaises(OSError):
                module.publish_playlist(self.playlist, "#EXTM3U\n")
        self.assertEqual(self.playlist.read_text(encoding="utf-8"), "another writer\n")
        self.assertEqual(self._temp_files(), [])

    def test_existing_target_replaced_during_write_is_not_overwritten(self) -> None:
        self.playlist.parent.mkdir(parents=True)
        self.playlist.write_text("old playlist\n", encoding="utf-8")
        real_fsync = os.fsync

        def concurrent_replace(fd: int) -> None:
            replacement = self.playlist.parent / "another-writer.m3u"
            replacement.write_text("newer playlist\n", encoding="utf-8")
            os.replace(replacement, self.playlist)
            real_fsync(fd)

        with patch.object(module.os, "fsync", side_effect=concurrent_replace):
            with self.assertRaises(OSError):
                module.publish_playlist(self.playlist, "#EXTM3U\n")
        self.assertEqual(self.playlist.read_text(encoding="utf-8"), "newer playlist\n")
        self.assertEqual(self._temp_files(), [])


if __name__ == "__main__":
    unittest.main()
