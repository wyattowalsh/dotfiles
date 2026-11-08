#!/usr/bin/env python3
"""Private delivery-profile fixtures, including a real two-second FLAC import."""

import hashlib
import importlib.util
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from contextlib import closing
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "delivery", ROOT / "rig/bootstrap/music-delivery-profile.py"
)
D = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(D)


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="delivery-profile-fixture-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.canonical = self.root / "canonical"
        self.canonical.mkdir(mode=0o700)
        self.output = self.root / "delivery"
        self.database = self.root / "library.db"
        with closing(sqlite3.connect(self.database)) as db:
            db.execute("CREATE TABLE fixture (id INTEGER)")
            db.commit()
        self.database.chmod(0o600)
        self.original_path = self.root / "original-config.yaml"
        self.original = {
            "library": str(self.database),
            "directory": str(self.canonical),
            "paths": {
                "default": "$albumartist/$album/$title",
                "singleton": "$artist/$album/$title",
            },
            "plugins": ["fetchart", "embedart", "chroma"],
            "include": ["unread-user-overlay.yaml"],
            "import": {"write": True, "autotag": True, "move": True},
        }
        self.original_path.write_text(yaml.safe_dump(self.original))
        self.original_path.chmod(0o600)
        self.consumer = {
            "schema": "mba-beets-consumer-prepared-v154",
            "prepared": True,
            "all_effective_item_paths_rebased_by_Beets_2_14": True,
            "raw_BLOB_paths_unchanged": True,
            "publication_sha256": "a" * 64,
            "candidate_database": str(self.database),
            "candidate_config": str(self.original_path),
            "config_sha256": self.ref(self.original_path)["sha256"],
            "effective_directory": str(self.canonical),
        }
        self.operator = {
            "schema_version": 1,
            "publication_state": "E1",
            "media_root": str(self.canonical),
        }
        self.operator_ref = self.save("operator.json", self.operator)
        self.publication = {
            "schema": "music-E1-publication-completed-v1",
            "published": True,
            "full_source_and_target_hash_comparison": True,
            "manifest_sha256": "b" * 64,
            "operator_contract_sha256": self.operator_ref["sha256"],
        }
        self.publication_ref = self.save("publication.json", self.publication)
        self.consumer["publication_sha256"] = self.publication_ref["sha256"]
        self.consumer["manifest_sha256"] = self.publication["manifest_sha256"]
        self.consumer_ref = self.save("consumer.json", self.consumer)

    def ref(self, path):
        return {
            "path": str(path),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }

    def save(self, name, value):
        path = self.root / name
        path.write_text(json.dumps(value))
        path.chmod(0o600)
        return self.ref(path)

    def prepare(self, apply=True):
        return D.prepare(
            self.consumer_ref,
            self.publication_ref,
            self.operator_ref,
            self.output,
            apply,
        )

    def test_preview_writes_nothing_and_preparation_preserves_original(self):
        db_before, original_before = (
            self.database.read_bytes(),
            self.original_path.read_bytes(),
        )
        self.assertTrue(self.prepare(False)["dry_run"])
        self.assertFalse(self.output.exists())
        self.assertFalse(self.prepare()["reused"])
        self.assertTrue(self.prepare()["reused"])
        self.assertEqual(self.database.read_bytes(), db_before)
        self.assertEqual(self.original_path.read_bytes(), original_before)
        config = yaml.safe_load((self.output / "config.yaml").read_text())
        self.assertEqual(config["plugins"], [])
        self.assertEqual(config["include"], [])
        self.assertFalse(config["import"]["write"])
        self.assertFalse(config["import"]["autotag"])
        self.assertEqual(config["paths"], self.original["paths"])
        self.assertEqual((self.output / "config.yaml").stat().st_mode & 0o777, 0o600)

    def test_unqualified_consumer_is_refused(self):
        self.consumer["prepared"] = False
        self.consumer_ref = self.save("consumer.json", self.consumer)
        with self.assertRaisesRegex(ValueError, "qualified_consumer"):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_operator_root_mismatch_is_refused(self):
        self.operator["media_root"] = str(self.root)
        self.operator_ref = self.save("operator.json", self.operator)
        self.publication["operator_contract_sha256"] = self.operator_ref["sha256"]
        self.publication_ref = self.save("publication.json", self.publication)
        self.consumer["publication_sha256"] = self.publication_ref["sha256"]
        self.consumer_ref = self.save("consumer.json", self.consumer)
        with self.assertRaisesRegex(ValueError, "operator_root"):
            self.prepare()

    def test_configuration_drift_is_refused(self):
        self.original_path.write_text("library: changed\n")
        with self.assertRaisesRegex(ValueError, "reference_changed"):
            self.prepare()

    def test_same_root_wrong_publication_is_refused(self):
        self.publication["manifest_sha256"] = "c" * 64
        self.publication_ref = self.save("publication.json", self.publication)
        with self.assertRaisesRegex(ValueError, "consumer_publication_operator_join"):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_same_root_wrong_operator_is_refused(self):
        self.operator["epoch"] = "other-accepted-E1"
        self.operator_ref = self.save("operator.json", self.operator)
        with self.assertRaisesRegex(ValueError, "consumer_publication_operator_join"):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_consumer_manifest_mismatch_is_refused(self):
        self.consumer["manifest_sha256"] = "c" * 64
        self.consumer_ref = self.save("consumer.json", self.consumer)
        with self.assertRaisesRegex(ValueError, "consumer_publication_operator_join"):
            self.prepare()

    def test_unverified_publication_is_refused(self):
        self.publication["full_source_and_target_hash_comparison"] = False
        self.publication_ref = self.save("publication.json", self.publication)
        self.consumer["publication_sha256"] = self.publication_ref["sha256"]
        self.consumer_ref = self.save("consumer.json", self.consumer)
        with self.assertRaisesRegex(ValueError, "consumer_publication_operator_join"):
            self.prepare()

    def test_consumed_or_changed_profile_is_never_overwritten(self):
        self.prepare()
        output = self.output / "config.yaml"
        output.write_text("changed")
        with self.assertRaises(ValueError):
            self.prepare()
        self.assertEqual(output.read_text(), "changed")

    def test_profile_cannot_live_in_canonical_root(self):
        self.output = self.canonical / "profile"
        with self.assertRaisesRegex(ValueError, "separate_profile"):
            self.prepare()

    @unittest.skipUnless(shutil.which("ffmpeg"), "prepared FFmpeg unavailable")
    def test_real_import_preserves_bytes_tags_art_and_creates_new_id(self):
        from mutagen.flac import FLAC, Picture

        # Initialize the real disposable database using the same prepared CLI.
        self.database.unlink()
        bootstrap = self.root / "bootstrap"
        bootstrap.mkdir(mode=0o700)
        bootstrap_config = {
            "library": str(self.database),
            "directory": str(self.canonical),
            "plugins": [],
            "include": [],
            "paths": self.original["paths"],
            "import": D.POLICY,
        }
        (bootstrap / "config.yaml").write_text(yaml.safe_dump(bootstrap_config))
        (bootstrap / "config.yaml").chmod(0o600)
        env = {
            "HOME": str(self.root),
            "BEETSDIR": str(bootstrap),
            "PATH": "/usr/bin:/bin",
        }
        command = [sys.executable, "-I", "-B", "-m", "beets"]
        subprocess.run(
            command + ["ls"],
            env=env,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            check=True,
        )
        self.database.chmod(0o600)
        inbox = self.root / "inbox"
        inbox.mkdir(mode=0o700)
        audio = inbox / "Special track.flac"
        subprocess.run(
            [
                str(Path(shutil.which("ffmpeg")).resolve()),
                "-nostdin",
                "-v",
                "error",
                "-f",
                "lavfi",
                "-i",
                "anullsrc=r=44100:cl=mono",
                "-t",
                "2",
                "-c:a",
                "flac",
                "-y",
                str(audio),
            ],
            check=True,
            capture_output=True,
        )
        media = FLAC(audio)
        media["artist"], media["albumartist"] = ["Fixture Artist"], ["Fixture Artist"]
        media["album"], media["title"] = ["Fixture Release"], ["Track (Extended Mix)"]
        media["version"], media["comment"] = (
            ["Extended Mix"],
            ["Fixture special-release note"],
        )
        media["lyrics"] = ["Fixture original lyric text"]
        picture = Picture()
        picture.type, picture.mime, picture.desc = (
            3,
            "image/png",
            "Fixture original art",
        )
        picture.width, picture.height, picture.depth = 1, 1, 24
        picture.data = b"fixture-picture-bytes"
        media.add_picture(picture)
        media.save()
        baseline = inbox / "Radio track.flac"
        shutil.copyfile(audio, baseline)
        old = FLAC(baseline)
        old["title"], old["version"] = ["Track (Radio Edit)"], ["Radio Edit"]
        old.save()
        subprocess.run(
            command + ["import", "--quiet", "--copy", "--singletons", str(baseline)],
            env=env,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            check=True,
        )
        with closing(sqlite3.connect(self.database)) as db:
            before_ids = {row[0] for row in db.execute("SELECT id FROM items")}
        self.assertEqual(len(before_ids), 1)
        before_hash = self.ref(audio)["sha256"]
        tags_before = dict(FLAC(audio).tags)
        art_before = [p.write() for p in FLAC(audio).pictures]
        self.prepare()
        # If BEETSDIR isolation fails, this normal-user plugin would write a marker.
        normal = self.root / ".config/beets"
        normal.mkdir(parents=True)
        marker = self.root / "unexpected-plugin-loaded"
        plugin_dir = self.root / "plugins"
        plugin_dir.mkdir()
        (plugin_dir / "unexpected_plugin.py").write_text(
            "from beets.plugins import BeetsPlugin\n"
            "from pathlib import Path\n"
            "class Unexpected(BeetsPlugin):\n"
            " def __init__(self):\n"
            f"  Path({str(marker)!r}).write_text('loaded')\n"
            "  super().__init__()\n"
        )
        (normal / "config.yaml").write_text(
            yaml.safe_dump(
                {
                    "plugins": ["unexpected_plugin"],
                    "pluginpath": [str(plugin_dir)],
                    "import": {"write": True},
                }
            )
        )
        env["BEETSDIR"] = str(self.output)
        subprocess.run(
            command + ["import", "--quiet", "--copy", "--singletons", str(audio)],
            env=env,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            check=True,
        )
        with closing(sqlite3.connect(self.database)) as db:
            rows = db.execute("SELECT id,path,title,artist,album FROM items").fetchall()
        (new,) = [row for row in rows if row[0] not in before_ids]
        # Beets 2.14 can store relative raw BLOBs. The actual CLI resolves the
        # effective path against this profile's bound directory, as the existing
        # import verifier does; raw SQL paths alone are not effective-path proof.
        listed = subprocess.run(
            command + ["ls", "-p", f"id:{new[0]}"],
            env=env,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            check=True,
        )
        destination = Path(os.fsdecode(listed.stdout).strip())
        self.assertNotIn(new[0], before_ids)
        self.assertTrue(destination.is_relative_to(self.canonical))
        self.assertNotEqual(destination, audio)
        self.assertEqual(
            new[2:], ("Track (Extended Mix)", "Fixture Artist", "Fixture Release")
        )
        self.assertEqual(self.ref(destination)["sha256"], before_hash)
        self.assertEqual(self.ref(audio)["sha256"], before_hash)
        self.assertEqual(dict(FLAC(destination).tags), tags_before)
        self.assertEqual([p.write() for p in FLAC(destination).pictures], art_before)
        self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
