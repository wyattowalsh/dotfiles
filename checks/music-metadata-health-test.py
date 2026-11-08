#!/usr/bin/env python3
"""Offline, synthetic contract tests for the fixture-only metadata health CLI."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("music-metadata-health.py")
DIMENSIONS = ("recording", "release", "lyrics", "artwork")
STATES = (
    "missing",
    "verified_correct",
    "verified_wrong",
    "unknown",
    "unavailable",
    "not_applicable",
)


def item(key: str, **states: str) -> dict[str, object]:
    """Construct a wholly invented item without consulting the music library."""
    result: dict[str, object] = {"key": key}
    for dimension in DIMENSIONS:
        state = states.get(dimension, "unknown")
        entry: dict[str, object] = {"state": state}
        if state in ("verified_correct", "verified_wrong"):
            entry.update(reviewed=True, provenance=["synthetic-human-review"])
        result[dimension] = entry
    return result


class MusicMetadataHealthTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="music-health-fixture-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.evidence = self.directory / "synthetic-evidence.json"

    def invoke(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment["UV_NO_CACHE"] = "1"
        environment["UV_NO_PROJECT"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        return subprocess.run(
            ["uv", "run", "python", str(SCRIPT), *arguments],
            cwd=self.directory,
            env=environment,
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )

    def write_evidence(self, evidence: object) -> None:
        self.evidence.write_text(json.dumps(evidence), encoding="utf-8")

    def invoke_evidence(self, evidence: object, *arguments: str) -> subprocess.CompletedProcess[str]:
        self.write_evidence(evidence)
        return self.invoke("--evidence", str(self.evidence), *arguments)

    def assert_rejected(self, result: subprocess.CompletedProcess[str], *private: str) -> None:
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertTrue(result.stderr.strip(), "expected a generic error label on stderr")
        self.assertNotIn(str(self.directory), result.stdout + result.stderr)
        for secret in private:
            self.assertNotIn(secret, result.stdout + result.stderr)

    def test_json_counts_include_all_states_and_clear_limitation(self) -> None:
        evidence = {
            "schema_version": 1,
            "items": [
                item(
                    "synthetic_A",
                    recording="verified_correct",
                    release="verified_wrong",
                    lyrics="missing",
                    artwork="not_applicable",
                ),
                item(
                    "synthetic_B",
                    recording="unknown",
                    release="unavailable",
                    lyrics="verified_correct",
                    artwork="verified_wrong",
                ),
            ],
        }
        result = self.invoke_evidence(evidence, "--format", "json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        output = json.loads(result.stdout)
        self.assertEqual(set(output), {"schema_version", "total_items", "counts", "limitation"})
        self.assertEqual(output["schema_version"], 1)
        self.assertEqual(output["total_items"], 2)
        self.assertEqual(set(output["counts"]), set(DIMENSIONS))
        for dimension in DIMENSIONS:
            self.assertEqual(set(output["counts"][dimension]), set(STATES))
            self.assertEqual(sum(output["counts"][dimension].values()), 2)
        self.assertEqual(output["counts"]["recording"]["verified_correct"], 1)
        self.assertEqual(output["counts"]["recording"]["unknown"], 1)
        self.assertEqual(output["counts"]["release"]["verified_wrong"], 1)
        self.assertEqual(output["counts"]["release"]["unavailable"], 1)
        self.assertEqual(output["counts"]["lyrics"]["missing"], 1)
        self.assertEqual(output["counts"]["lyrics"]["verified_correct"], 1)
        self.assertEqual(output["counts"]["artwork"]["not_applicable"], 1)
        self.assertEqual(output["counts"]["artwork"]["verified_wrong"], 1)
        self.assertIn("not independently verified", output["limitation"].lower())
        for private in ("synthetic_A", "synthetic_B", "synthetic-human-review", str(self.directory)):
            self.assertNotIn(private, result.stdout)

    def test_text_is_default_and_only_reports_aggregate_claims(self) -> None:
        result = self.invoke_evidence({"schema_version": 1, "items": [item("private_fixture_key")]})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertIn("1", result.stdout)
        self.assertIn("not independently verified", result.stdout.lower())
        self.assertNotIn("private_fixture_key", result.stdout)
        self.assertNotIn(str(self.directory), result.stdout)

    def test_evidence_argument_is_required_without_implicit_live_default(self) -> None:
        self.assert_rejected(self.invoke("--format", "json"))

    def test_malformed_and_empty_files_fail_closed(self) -> None:
        for content in ("", "{ this-is-not-json", "[]", "null"):
            with self.subTest(content=content):
                self.evidence.write_text(content, encoding="utf-8")
                self.assert_rejected(self.invoke("--evidence", str(self.evidence), "--format", "json"))

    def test_empty_items_and_wrong_schema_fail_closed(self) -> None:
        for evidence in (
            {"schema_version": 1, "items": []},
            {"schema_version": 2, "items": [item("made_up")]},
            {"schema_version": True, "items": [item("made_up")]},
            {"schema_version": 1},
        ):
            with self.subTest(evidence=evidence):
                self.assert_rejected(self.invoke_evidence(evidence))

    def test_duplicate_item_keys_fail_closed(self) -> None:
        evidence = {"schema_version": 1, "items": [item("duplicate_private_key"), item("duplicate_private_key")]}
        self.assert_rejected(self.invoke_evidence(evidence), "duplicate_private_key")

    def test_invalid_key_and_missing_dimension_fail_closed(self) -> None:
        for broken_item in (item("private/path"), item(""), item("a" * 65), {"key": "test", "recording": {"state": "unknown"}}):
            with self.subTest(broken_item=broken_item):
                self.assert_rejected(
                    self.invoke_evidence({"schema_version": 1, "items": [broken_item]}),
                    "private/path",
                )

    def test_unknown_state_and_unexpected_fields_fail_closed_without_echo(self) -> None:
        unknown_state = item("opaque_marker_123")
        unknown_state["lyrics"] = {"state": "secret_invalid_state_456"}
        unexpected_item = item("opaque_marker_123")
        unexpected_item["private_unexpected_field_789"] = "secret_payload_987"
        extra_dimension_field = item("opaque_marker_123")
        extra_dimension_field["artwork"] = {"state": "missing", "secret_field": "secret_payload_987"}
        for evidence in (
            {"schema_version": 1, "items": [unknown_state]},
            {"schema_version": 1, "items": [unexpected_item]},
            {"schema_version": 1, "items": [extra_dimension_field]},
            {"schema_version": 1, "items": [item("opaque_marker_123")], "secret_top_field": "secret_payload_987"},
        ):
            with self.subTest(evidence=evidence):
                self.assert_rejected(
                    self.invoke_evidence(evidence, "--format", "json"),
                    "opaque_marker_123",
                    "secret_invalid_state_456",
                    "secret_payload_987",
                    "private_unexpected_field_789",
                )

    def test_verified_claim_requires_true_review_and_sources(self) -> None:
        for dimension in DIMENSIONS:
            for entry in (
                {"state": "verified_correct", "reviewed": False, "provenance": ["synthetic-source"]},
                {"state": "verified_wrong", "provenance": ["synthetic-source"]},
                {"state": "verified_correct", "reviewed": True},
                {"state": "verified_wrong", "reviewed": True, "provenance": []},
                {"state": "verified_correct", "reviewed": True, "provenance": ["   "]},
                {"state": "verified_wrong", "reviewed": True, "provenance": ["synthetic-source", "synthetic-source"]},
            ):
                with self.subTest(dimension=dimension, entry=entry):
                    broken_item = item("private_unreviewed_claim")
                    broken_item[dimension] = entry
                    self.assert_rejected(
                        self.invoke_evidence({"schema_version": 1, "items": [broken_item]}),
                        "private_unreviewed_claim",
                        "synthetic-source",
                    )

    def test_missing_file_does_not_disclose_requested_path(self) -> None:
        private_path = self.directory / "private_missing_evidence_abc.json"
        self.assert_rejected(
            self.invoke("--evidence", str(private_path), "--format", "json"),
            "private_missing_evidence_abc.json",
        )


if __name__ == "__main__":
    unittest.main()
