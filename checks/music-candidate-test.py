#!/usr/bin/env python3
"""Candidate gates on private fixtures; no live library, network or services."""

import csv
from contextlib import closing
import hashlib
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
LOADER = importlib.machinery.SourceFileLoader('candidate', str(ROOT / 'rig/home/dot_local/bin/executable_music-candidate'))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
C = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(C)


class CandidateTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='music-candidate-fixture-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.library = self.root / 'canonical'
        self.inbox = self.root / 'inbox'
        self.ready = self.root / 'ready'
        for path in (self.library, self.inbox, self.ready):
            path.mkdir(mode=0o700)
        self.source = self.library / 'source.mp3'
        self.source.write_bytes(b'previous independently retained source')
        self.audio = self.inbox / 'test.flac'
        self.audio.write_bytes(b'flac-fixture')
        self.db = self.root / 'library.db'
        with closing(sqlite3.connect(self.db)) as db:
            db.execute('CREATE TABLE items(format TEXT, bitrate INTEGER, mb_albumid TEXT, mb_releasetrackid TEXT, title TEXT, artist TEXT, album TEXT)')
            db.execute("INSERT INTO items VALUES ('MP3',192000,'release','release-track','Song (Extended Mix)','Artist','Release')")
            db.commit()
        self.db.chmod(0o600)
        self.current = self.save('current.json', {'epoch': 'fixture-e1'})
        self.lock = self.root / 'writer.lock'
        self.lock.touch(mode=0o600)
        self.candidate = {
            'schema': 1, 'source_kind': 'slskd', 'candidate_id': 'slskd-fixture',
            'identity_status': 'review_required', 'canonical_effects': False,
            'local_path': str(self.audio), 'file_size': self.audio.stat().st_size,
            'file_sha256': C.file_hash(self.audio)[0], 'file_stamp': C.stamp(self.audio.stat()),
        }
        self.candidate_ref = self.save('candidate.json', self.candidate)
        self.row = {
            'Artist': 'Artist', 'Title': 'Song (Extended Mix)', 'Album': 'Release',
            'Length': '2', 'Format': 'flac', 'EditionId': 'edition-exact',
            'Version': 'extended', 'Evidence': 'release-track-proof',
            'IdentityStatus': 'source-anchored',
            'SourceEvidence': json.dumps({
                'library_root': str(self.library), 'beets_db': str(self.db),
                'metadata': {'release_id': 'release', 'release_track_id': 'release-track',
                             'title': 'Song (Extended Mix)', 'artist': 'Artist', 'album': 'Release'},
                'members': [{'path': str(self.source), 'sha256': C.file_hash(self.source)[0]}],
            }),
        }
        self.queue = self.root / 'missing.csv'
        self.write_queue()
        self.review = {
            'schema': 'music-candidate-identity-review-v1',
            'candidate_sha256': self.candidate['file_sha256'],
            'requirement_row_sha256': C.sha(C.encoded(self.row)),
            'edition_id': self.row['EditionId'], 'version': self.row['Version'],
            'identity_verified': True, 'evidence': [{'kind': 'fixture-release-evidence'}],
            'expected_tags': {'artist': 'Artist', 'title': 'Song (Extended Mix)', 'album': 'Release'},
        }
        self.review_ref = self.save('review.json', self.review)
        tool = Path('/usr/bin/true').resolve()
        tool_ref = {'path': str(tool), 'sha256': hashlib.sha256(tool.read_bytes()).hexdigest()}
        self.contract = {
            'schema': 'music-candidate-verification-v1', 'candidate': self.candidate_ref,
            'queue': self.ref(self.queue), 'row_sha256': C.sha(C.encoded(self.row)),
            'identity_review': self.review_ref, 'current_descriptor': self.current,
            'beets_database': self.ref(self.db), 'ffprobe': tool_ref, 'ffmpeg': tool_ref,
            'source_root': str(self.inbox), 'ready_root': str(self.ready),
            'writer_lock': str(self.lock), 'canonical_root': str(self.library),
        }
        self.contract_ref = self.save('contract.json', self.contract)

    def ref(self, path):
        return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

    def save(self, name, obj):
        path = self.root / name
        if path.exists():
            path.unlink()
        C.save(path, obj)
        return self.ref(path)

    def write_queue(self):
        with self.queue.open('w', newline='') as stream:
            writer = csv.DictWriter(stream, fieldnames=list(self.row))
            writer.writeheader()
            writer.writerow(self.row)
        self.queue.chmod(0o600)

    def fake_probe(self, argv, *, json_output=False):
        if json_output:
            return {'streams': [{'codec_type': 'audio', 'codec_name': 'flac', 'duration': '2.0'}],
                    'format': {'format_name': 'flac', 'tags': self.review['expected_tags']}}
        return {}

    def verified(self):
        with patch.object(C, 'run_checked', side_effect=self.fake_probe):
            proof = C.verify(self.contract_ref)
        return self.save('verified.json', proof)

    def stage(self, proof):
        with self.lock.open('r+b') as lock, patch.object(C.shutil, 'disk_usage', return_value=SimpleNamespace(free=64 * C.GIB)):
            return C.stage(proof, lock.fileno())

    def test_verify_and_stage_are_byte_preserving_and_idempotent(self):
        prior = self.source.read_bytes()
        proof = self.verified()
        first = self.stage(proof)
        second = self.stage(proof)
        self.assertTrue(first['ready'])
        self.assertTrue(second['reused'])
        self.assertEqual(Path(first['audio']['path']).read_bytes(), self.audio.read_bytes())
        self.assertEqual(self.source.read_bytes(), prior)
        self.assertFalse(first['canonical_effects'])
        self.assertFalse(first['Beets_imported'])

    def test_unreviewed_identity_is_held(self):
        self.review['identity_verified'] = False
        self.review_ref = self.save('review.json', self.review)
        self.contract['identity_review'] = self.review_ref
        ref = self.save('contract.json', self.contract)
        with self.assertRaisesRegex(ValueError, 'reviewed_exact_identity'):
            C.verify(ref)

    def test_wrong_actual_codec_is_held(self):
        def probe(argv, *, json_output=False):
            result = self.fake_probe(argv, json_output=json_output)
            if json_output:
                result['streams'][0]['codec_name'] = 'mp3'
            return result
        with patch.object(C, 'run_checked', side_effect=probe), self.assertRaisesRegex(ValueError, 'actual_codec'):
            C.verify(self.contract_ref)

    def test_reviewed_mix_metadata_is_not_erased(self):
        def probe(argv, *, json_output=False):
            result = self.fake_probe(argv, json_output=json_output)
            if json_output:
                result['format']['tags'] = self.review['expected_tags'] | {'title': 'Song (Radio Edit)'}
            return result
        with patch.object(C, 'run_checked', side_effect=probe), self.assertRaisesRegex(ValueError, 'metadata_mismatch'):
            C.verify(self.contract_ref)

    def test_probe_and_decoder_only_admit_local_protocols(self):
        calls = []

        def probe(argv, *, json_output=False):
            calls.append(argv)
            self.assertEqual(argv[argv.index('-protocol_whitelist') + 1], 'file,pipe')
            return self.fake_probe(argv, json_output=json_output)

        with patch.object(C, 'run_checked', side_effect=probe):
            C.verify(self.contract_ref)
        self.assertEqual(len(calls), 2)

    def test_already_present_format_is_not_promoted(self):
        with closing(sqlite3.connect(self.db)) as db:
            db.execute("UPDATE items SET format='FLAC'")
            db.commit()
        self.contract['beets_database'] = self.ref(self.db)
        ref = self.save('contract.json', self.contract)
        with self.assertRaisesRegex(ValueError, 'already_present'):
            C.verify(ref)

    def test_queue_change_invalidates_the_bound_row(self):
        self.queue.write_text(self.queue.read_text() + '\n')
        with self.assertRaisesRegex(ValueError, 'control_pin'):
            C.verify(self.contract_ref)

    def test_candidate_change_during_decode_is_held(self):
        def probe(argv, *, json_output=False):
            if not json_output:
                self.audio.write_bytes(b'changed-content')
            return self.fake_probe(argv, json_output=json_output)
        with patch.object(C, 'run_checked', side_effect=probe), self.assertRaisesRegex(ValueError, 'file_hash_changed'):
            C.verify(self.contract_ref)

    def test_database_change_after_verification_prevents_staging(self):
        proof = self.verified()
        with closing(sqlite3.connect(self.db)) as db:
            db.execute("UPDATE items SET bitrate=320000")
            db.commit()
        with self.assertRaisesRegex(ValueError, 'file_hash_changed'):
            self.stage(proof)
        self.assertEqual(list(self.ready.iterdir()), [])

    def test_partial_handoff_is_never_replayed(self):
        proof = self.verified()
        partial = self.ready / self.candidate['candidate_id']
        partial.mkdir(mode=0o700)
        C.save(partial / 'PENDING.private.json', {'automatic_replay': False})
        with self.assertRaisesRegex(ValueError, 'reconciliation_no_replay'):
            self.stage(proof)
        self.assertEqual(len(list(partial.iterdir())), 1)

    def test_unrelated_fd_cannot_stage(self):
        proof = self.verified()
        with self.source.open('rb') as unrelated, self.assertRaisesRegex(ValueError, 'native_writer'):
            C.stage(proof, unrelated.fileno())

    def test_capacity_failure_creates_no_partial_handoff(self):
        proof = self.verified()
        with self.lock.open('r+b') as lock, \
                patch.object(C.shutil, 'disk_usage', return_value=SimpleNamespace(free=C.GIB)), \
                self.assertRaisesRegex(ValueError, 'capacity_floor'):
            C.stage(proof, lock.fileno())
        self.assertEqual(list(self.ready.iterdir()), [])

    def test_ready_destination_cannot_be_canonical(self):
        self.contract['ready_root'] = str(self.library)
        ref = self.save('contract.json', self.contract)
        with self.assertRaisesRegex(ValueError, 'must_not_be_canonical'):
            C.verify(ref)

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'prepared FFmpeg tools unavailable')
    def test_real_flac_is_probed_and_fully_decoded(self):
        ffmpeg = Path(shutil.which('ffmpeg')).resolve()
        ffprobe = Path(shutil.which('ffprobe')).resolve()
        subprocess.run([str(ffmpeg), '-nostdin', '-v', 'error', '-f', 'lavfi',
                        '-i', 'anullsrc=r=44100:cl=mono', '-t', '2', '-c:a', 'flac',
                        '-metadata', 'artist=Artist', '-metadata', 'title=Song (Extended Mix)',
                        '-metadata', 'album=Release', '-y', str(self.audio)], check=True)
        self.candidate.update(file_size=self.audio.stat().st_size,
                              file_sha256=C.file_hash(self.audio)[0], file_stamp=C.stamp(self.audio.stat()))
        self.contract['candidate'] = self.save('candidate.json', self.candidate)
        self.review['candidate_sha256'] = self.candidate['file_sha256']
        self.contract['identity_review'] = self.save('review.json', self.review)
        for key, tool in [('ffmpeg', ffmpeg), ('ffprobe', ffprobe)]:
            self.contract[key] = {'path': str(tool), 'sha256': hashlib.sha256(tool.read_bytes()).hexdigest()}
        ref = self.save('contract.json', self.contract)
        proof = C.verify(ref)
        self.assertTrue(proof['complete_decode_passed'])
        self.assertEqual(proof['actual_codec'], 'flac')
        self.assertEqual(proof['actual_container'], 'flac')

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'prepared FFmpeg tools unavailable')
    def test_real_flac_inside_matroska_is_held_despite_flac_extension(self):
        ffmpeg = Path(shutil.which('ffmpeg')).resolve()
        ffprobe = Path(shutil.which('ffprobe')).resolve()
        subprocess.run([str(ffmpeg), '-nostdin', '-v', 'error', '-f', 'lavfi',
                        '-i', 'anullsrc=r=44100:cl=mono', '-t', '2', '-c:a', 'flac',
                        '-metadata', 'artist=Artist', '-metadata', 'title=Song (Extended Mix)',
                        '-metadata', 'album=Release', '-f', 'matroska', '-y', str(self.audio)], check=True)
        self.candidate.update(file_size=self.audio.stat().st_size,
                              file_sha256=C.file_hash(self.audio)[0], file_stamp=C.stamp(self.audio.stat()))
        self.contract['candidate'] = self.save('candidate.json', self.candidate)
        self.review['candidate_sha256'] = self.candidate['file_sha256']
        self.contract['identity_review'] = self.save('review.json', self.review)
        for key, tool in [('ffmpeg', ffmpeg), ('ffprobe', ffprobe)]:
            self.contract[key] = {'path': str(tool), 'sha256': hashlib.sha256(tool.read_bytes()).hexdigest()}
        ref = self.save('contract.json', self.contract)
        with self.assertRaisesRegex(ValueError, 'actual_container_mismatch'):
            C.verify(ref)
        self.assertEqual(list(self.ready.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
