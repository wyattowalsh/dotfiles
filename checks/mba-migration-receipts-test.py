"""Synthetic-only contract tests; no host, repository or media access."""

from __future__ import annotations

import copy
import json
import os
import subprocess
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("mba-migration-receipts.py")
NOW = "2026-10-12T12:00:00Z"
HASH_A = "a" * 64
HASH_B = "b" * 64
HASH_C = "c" * 64
HASH_D = "d" * 64
SCOPE = {
    "host_id": "host-synthetic", "endpoint_id": "endpoint-synthetic",
    "volume_id": "volume-synthetic", "container_id": "container-synthetic",
    "config_sha256": HASH_A, "epoch_id": "epoch-synthetic",
    "manifest_sha256": HASH_B, "source_sha256": HASH_C,
    "installed_sha256": HASH_D, "repository_id": "repository-synthetic",
}


def receipt(leaf_id: str, instance_id: str = "one") -> dict:
    return {
        "leaf_id": leaf_id, "instance_id": instance_id,
        "status": "verified", "coverage": "production_claimed",
        "observed_at": "2026-10-12T11:00:00Z",
        "expires_at": "2026-10-12T13:00:00Z",
        "scope": copy.deepcopy(SCOPE),
        "operation_id": "inspect-synthetic", "target_ids": ["target-synthetic"],
        "recipient_id": "recipient-synthetic", "budget_id": "budget-synthetic",
        "approval": {
            "reference_id": "approval-reference-synthetic", "decision": "granted",
            "operation_id": "inspect-synthetic", "target_ids": ["target-synthetic"],
            "host_id": SCOPE["host_id"], "endpoint_id": SCOPE["endpoint_id"],
            "epoch_id": SCOPE["epoch_id"], "recipient_id": "recipient-synthetic",
            "budget_id": "budget-synthetic", "scope": copy.deepcopy(SCOPE),
        },
        "checks": [{"name": "synthetic-check", "result": "pass"}],
        "rollback": {"reference_id": "rollback-reference-synthetic", "ready": True},
        "invalidations": [],
    }


def requirement(leaf_id: str, *, instances: list[str] | None = None,
                depends_on: list[str] | None = None, condition: dict | None = None) -> dict:
    return {"id": leaf_id, "leaf_id": leaf_id, "instances": instances or ["one"],
            "depends_on": depends_on or [], "condition": condition}


def fixture() -> dict:
    return {
        "schema_version": 1, "scope": copy.deepcopy(SCOPE),
        "receipts": [receipt("P03")],
        "requirements": [requirement("P03")],
        "instance_sets": [], "decisions": [],
    }


class ReceiptTests(unittest.TestCase):
    def invoke(self, data: dict | bytes, now: str = NOW) -> tuple[int, dict]:
        payload = data if isinstance(data, bytes) else json.dumps(data).encode("utf-8")
        env = os.environ.copy()
        env.update(UV_NO_PROJECT="1", PYTHONDONTWRITEBYTECODE="1")
        run = subprocess.run(
            ["uv", "run", "--offline", "--no-project", "python", "-I", str(SCRIPT), "--now", now],
            input=payload, capture_output=True, timeout=20, check=False, env=env,
        )
        self.assertEqual(run.stderr, b"", run.stderr.decode(errors="replace"))
        return run.returncode, json.loads(run.stdout)

    def blocked(self, data: dict | bytes, reason: str) -> None:
        code, report = self.invoke(data)
        self.assertEqual(code, 1, report)
        self.assertEqual(report["status"], "blocked")
        self.assertIn(reason, report["reasons"])
        self.assertEqual(report["coverage"], "unverified")
        self.assertIs(report["operation_authorized"], False)

    def invalid(self, data: dict | bytes, reason: str) -> None:
        code, report = self.invoke(data)
        self.assertEqual(code, 2, report)
        self.assertEqual(report["status"], "unknown")
        self.assertEqual(report["reason"], reason)
        self.assertIs(report["operation_authorized"], False)

    def test_self_asserted_verified_is_only_matching_assertions(self) -> None:
        code, report = self.invoke(fixture())
        self.assertEqual(code, 0, report)
        self.assertEqual(report["status"], "matching_assertions")
        self.assertEqual(report["coverage"], "unverified")
        self.assertIs(report["operation_authorized"], False)
        self.assertNotIn("PASS", json.dumps(report))

    def test_scope_status_freshness_and_invalidation_fail_closed(self) -> None:
        for path, value, reason in (
            (("receipts", 0, "status"), "PASS", "invalid_status"),
            (("receipts", 0, "status"), "partial", "unsatisfied_status"),
            (("receipts", 0, "status"), "blocked", "unsatisfied_status"),
            (("receipts", 0, "status"), "failed", "unsatisfied_status"),
            (("receipts", 0, "status"), "not_started", "unsatisfied_status"),
            (("receipts", 0, "coverage"), "trusted", "invalid_coverage"),
            (("receipts", 0, "scope", "host_id"), "other-host", "scope_mismatch"),
            (("receipts", 0, "scope", "endpoint_id"), "other-endpoint", "scope_mismatch"),
            (("receipts", 0, "scope", "volume_id"), "other-volume", "scope_mismatch"),
            (("receipts", 0, "scope", "container_id"), "other-container", "scope_mismatch"),
            (("receipts", 0, "scope", "config_sha256"), HASH_B, "scope_mismatch"),
            (("receipts", 0, "scope", "epoch_id"), "other-epoch", "scope_mismatch"),
            (("receipts", 0, "scope", "manifest_sha256"), HASH_A, "scope_mismatch"),
            (("receipts", 0, "scope", "source_sha256"), HASH_A, "scope_mismatch"),
            (("receipts", 0, "scope", "installed_sha256"), HASH_A, "scope_mismatch"),
            (("receipts", 0, "scope", "repository_id"), "other-repository", "scope_mismatch"),
            (("receipts", 0, "observed_at"), "2026-10-12T12:00:01Z", "future_observation"),
            (("receipts", 0, "expires_at"), NOW, "expired_receipt"),
            (("receipts", 0, "invalidations"), ["new_write"], "invalidated_receipt"),
        ):
            with self.subTest(path=path):
                data = fixture()
                node = data
                for key in path[:-1]:
                    node = node[key]
                node[path[-1]] = value
                if reason.startswith("invalid_") and reason not in ("invalidated_receipt",):
                    self.invalid(data, reason)
                else:
                    self.blocked(data, reason)
        code, report = self.invoke(fixture(), now="2026-10-12T13:00:00Z")
        self.assertEqual((code, report["status"]), (1, "blocked"))

    def test_approval_checks_and_rollback_are_only_metadata_but_required(self) -> None:
        for path, value, reason in (
            (("receipts", 0, "approval", "decision"), "denied", "approval_denied_or_pending"),
            (("receipts", 0, "approval", "decision"), "pending", "approval_denied_or_pending"),
            (("receipts", 0, "approval", "operation_id"), "other-op", "approval_scope_mismatch"),
            (("receipts", 0, "approval", "target_ids"), ["other-target"], "approval_scope_mismatch"),
            (("receipts", 0, "approval", "host_id"), "other-host", "approval_scope_mismatch"),
            (("receipts", 0, "approval", "endpoint_id"), "other-endpoint", "approval_scope_mismatch"),
            (("receipts", 0, "approval", "epoch_id"), "other-epoch", "approval_scope_mismatch"),
            (("receipts", 0, "approval", "recipient_id"), "other-recipient", "approval_scope_mismatch"),
            (("receipts", 0, "approval", "budget_id"), "other-budget", "approval_scope_mismatch"),
            (("receipts", 0, "approval", "scope", "repository_id"), "other-repo", "approval_scope_mismatch"),
            (("receipts", 0, "approval", "scope", "config_sha256"), HASH_B, "approval_scope_mismatch"),
            (("receipts", 0, "checks", 0, "result"), "fail", "check_unsatisfied"),
            (("receipts", 0, "checks", 0, "result"), "unknown", "check_unsatisfied"),
            (("receipts", 0, "rollback", "ready"), False, "rollback_not_ready"),
        ):
            with self.subTest(path=path):
                data = fixture()
                node = data
                for key in path[:-1]:
                    node = node[key]
                node[path[-1]] = value
                self.blocked(data, reason)
        data = fixture()
        data["receipts"][0]["approval"]["reference_id"] = "approval-reference-synthetic"
        self.assertEqual(self.invoke(data)[1]["status"], "matching_assertions")

    def test_and_join_requires_every_selected_instance_and_current_parent(self) -> None:
        data = fixture()
        data["instance_sets"] = [{"leaf_id": "P04", "selected": ["mba", "mbp"]}]
        data["requirements"].append(requirement("P04", instances=["*"], depends_on=["P03"]))
        data["receipts"].extend([receipt("P04", "mba"), receipt("P04", "mbp")])
        self.assertEqual(self.invoke(data)[1]["status"], "matching_assertions")
        missing = copy.deepcopy(data)
        missing["receipts"].pop()
        self.blocked(missing, "missing_receipt")
        partial = copy.deepcopy(data)
        partial["receipts"][0]["status"] = "partial"
        self.blocked(partial, "unsatisfied_status")
        self.blocked(partial, "unsatisfied_dependency")
        empty = copy.deepcopy(data)
        empty["instance_sets"][0]["selected"] = []
        self.invalid(empty, "invalid_schema")
        unknown = copy.deepcopy(data)
        unknown["instance_sets"] = []
        self.blocked(unknown, "missing_instance_set")
        unused = fixture()
        unused["instance_sets"] = [{"leaf_id": "P03", "selected": ["one"]}]
        self.invalid(unused, "unreferenced_instance_set")

    def test_dependency_edges_reject_duplicates_cycles_and_gaps(self) -> None:
        data = fixture()
        data["requirements"].append(requirement("P04", depends_on=["P03"]))
        data["receipts"].append(receipt("P04"))
        self.assertEqual(self.invoke(data)[1]["status"], "matching_assertions")
        duplicate = copy.deepcopy(data)
        duplicate["requirements"][1]["depends_on"] = ["P03", "P03"]
        self.invalid(duplicate, "duplicate_dependency")
        cycle = copy.deepcopy(data)
        cycle["requirements"][0]["depends_on"] = ["P04"]
        self.invalid(cycle, "cyclic_dependency")
        dangling = copy.deepcopy(data)
        dangling["requirements"][1]["depends_on"] = ["P05"]
        self.invalid(dangling, "missing_dependency")
        duplicate = copy.deepcopy(data)
        duplicate["receipts"].append(receipt("P04"))
        self.invalid(duplicate, "duplicate_receipt")
        duplicate = copy.deepcopy(data)
        duplicate["requirements"].append(requirement("P03"))
        self.invalid(duplicate, "duplicate_requirement")

    def test_diamond_graph_is_acyclic_and_leaf_failures_block_every_and_path(self) -> None:
        data = fixture()
        data["requirements"].extend([
            requirement("A", depends_on=["P03"]),
            requirement("B", depends_on=["P03"]),
            requirement("C", depends_on=["A", "B"]),
        ])
        data["receipts"].extend([receipt("A"), receipt("B"), receipt("C")])
        self.assertEqual(self.invoke(data)[1]["status"], "matching_assertions")
        data["receipts"][2]["status"] = "failed"
        self.blocked(data, "unsatisfied_dependency")

    def test_conditional_branches_need_complete_decisions_and_fail_never_grants_capacity(self) -> None:
        data = fixture()
        data["requirements"] += [
            requirement("PASS", depends_on=["P03"], condition={"id": "gate", "when": "pass"}),
            requirement("FAIL", depends_on=["P03"], condition={"id": "gate", "when": "fail"}),
        ]
        data["decisions"] = [{"id": "gate", "outcome": "pass"}]
        data["receipts"].append(receipt("PASS"))
        self.assertEqual(self.invoke(data)[1]["status"], "matching_assertions")
        unknown = copy.deepcopy(data)
        unknown["decisions"][0]["outcome"] = "unknown"
        self.blocked(unknown, "conditional_unknown")
        missing = copy.deepcopy(data)
        missing["decisions"] = []
        self.blocked(missing, "conditional_unknown")
        gap = copy.deepcopy(data)
        gap["requirements"].pop()
        self.blocked(gap, "conditional_branch_gap")
        failed = copy.deepcopy(data)
        failed["decisions"][0]["outcome"] = "fail"
        failed["receipts"].pop()
        failed["receipts"].append(receipt("FAIL"))
        self.blocked(failed, "conditional_failed")
        inactive = copy.deepcopy(data)
        inactive["requirements"][1]["depends_on"] = ["FAIL"]
        self.blocked(inactive, "dependency_inactive")

    def test_malformed_nested_fields_and_time_bounds_are_unknown(self) -> None:
        for path, value, reason in (
            (("scope", "host_id"), "/Users/private/path", "invalid_identity"),
            (("scope", "config_sha256"), HASH_A.upper(), "invalid_hash"),
            (("receipts", 0, "scope", "manifest_sha256"), "bad", "invalid_hash"),
            (("receipts", 0, "observed_at"), "2026-10-12T11:00:00+00:00", "invalid_timestamp"),
            (("receipts", 0, "expires_at"), "2026-02-30T00:00:00Z", "invalid_timestamp"),
            (("receipts", 0, "invalidations"), ["unknown_signal"], "invalid_invalidation"),
            (("receipts", 0, "rollback", "ready"), 1, "invalid_rollback"),
            (("receipts", 0, "checks"), [], "invalid_schema"),
            (("receipts", 0, "target_ids"), [], "invalid_schema"),
            (("receipts", 0, "approval", "decision"), "skip", "invalid_approval"),
        ):
            with self.subTest(path=path):
                data = fixture()
                node = data
                for key in path[:-1]:
                    node = node[key]
                node[path[-1]] = value
                self.invalid(data, reason)
        data = fixture()
        data["receipts"][0]["expires_at"] = "2026-10-14T00:00:00Z"
        self.blocked(data, "stale_receipt")
        data = fixture()
        data["receipts"][0]["observed_at"] = "2026-10-11T11:00:00Z"
        self.blocked(data, "stale_receipt")
        data = fixture()
        data["receipts"][0]["checks"].append(copy.deepcopy(data["receipts"][0]["checks"][0]))
        self.invalid(data, "duplicate_check")
        code, report = self.invoke(fixture())
        self.assertEqual(code, 0)
        self.assertNotIn("approval-reference-synthetic", json.dumps(report))
        self.assertNotIn("host-synthetic", json.dumps(report))

    def test_clock_input_must_be_canonical_utc(self) -> None:
        code, report = self.invoke(fixture(), now="2026-10-12T12:00:00+00:00")
        self.assertEqual((code, report["reason"]), (2, "invalid_timestamp"))
        code, report = self.invoke(fixture(), now="2026-1-2T12:00:00Z")
        self.assertEqual((code, report["reason"]), (2, "invalid_timestamp"))
        code, report = self.invoke(fixture(), now="2026-10-12T12:00:00Z")
        self.assertEqual((code, report["status"]), (0, "matching_assertions"))

    def test_bounded_strict_json_and_schema_fail_closed(self) -> None:
        self.invalid(b'{"schema_version":1,"schema_version":1}', "duplicate_field")
        self.invalid(b'{"schema_version":NaN}', "invalid_number")
        self.invalid(b'{"schema_version":Infinity}', "invalid_number")
        self.invalid(b' ' * 65_537, "input_too_large")
        self.invalid(b'broken json', "invalid_json")
        for field, value in (("schema_version", True), ("schema_version", 2),
                             ("surprise", "extra")):
            with self.subTest(field=field, value=value):
                data = fixture()
                data[field] = value
                self.invalid(data, "invalid_schema")


if __name__ == "__main__":
    unittest.main()
