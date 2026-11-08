"""Bounded, synthetic lease-policy fixtures. No host or coordinator is contacted."""

from __future__ import annotations

import json
import os
import subprocess
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("mba-resource-leases.py")


def acquire(
    *,
    at: str = "2026-10-12T00:00:00Z",
    owner: str = "owner-a",
    operation: str = "task-a",
    identity: str = "incarnation-a",
    host: str = "MBA",
    kind: str = "heavy_io",
    repository: str | None = None,
    connector: str | None = None,
    requested: list[str] | None = None,
    expires_at: str = "2026-10-12T00:10:00Z",
) -> dict:
    required = ["S", f"H:{host}"]
    if kind in ("repository_io", "migration_transition"):
        required.append(f"K:{repository}")
    if kind in ("music_write", "migration_transition"):
        required.append("W")
    if kind in ("connector_change", "migration_transition"):
        required.append(f"M:{connector}")
    return {
        "action": "acquire",
        "at": at,
        "owner": owner,
        "operation": operation,
        "identity": identity,
        "host": host,
        "kind": kind,
        "repository": repository,
        "connector": connector,
        "requested": required if requested is None else requested,
        "expires_at": expires_at,
    }


def transition(
    action: str, *, at: str = "2026-10-12T00:02:00Z",
    owner: str = "owner-a", operation: str = "task-a",
    identity: str = "incarnation-a", outcome: str | None = None,
    witness: dict | None = None, writer_fence: int | None = None,
) -> dict:
    return {
        "action": action, "at": at, "owner": owner,
        "operation": operation, "identity": identity, "outcome": outcome,
        "witness": witness, "writer_fence": writer_fence,
    }


def stop_witness(
    *, stopped_at: str = "2026-10-12T00:03:00Z",
    owner: str = "owner-a", operation: str = "task-a",
    identity: str = "incarnation-a", witness_id: str = "witness-a",
) -> dict:
    return {
        "witness_id": witness_id, "stopped_at": stopped_at,
        "owner": owner, "operation": operation, "identity": identity,
    }


def scenario(*events: dict) -> dict:
    return {"schema_version": 1, "events": list(events)}


class LeasePolicyTests(unittest.TestCase):
    def invoke(self, payload: dict | bytes) -> tuple[int, dict]:
        content = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        env = os.environ.copy()
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        result = subprocess.run(
            ["uv", "run", "--offline", "--no-project", "python", "-I", str(SCRIPT)],
            input=content,
            capture_output=True,
            check=False,
            timeout=15,
            env=env,
        )
        self.assertFalse(result.stderr, result.stderr.decode(errors="replace"))
        return result.returncode, json.loads(result.stdout)

    def test_full_set_is_acquired_as_simulation_not_operational_permission(self) -> None:
        code, report = self.invoke(scenario(acquire()))
        self.assertEqual(code, 0, report)
        self.assertEqual(report["status"], "SIMULATED_ONLY")
        self.assertEqual(report["events"][0]["result"], "acquired")
        self.assertEqual(report["held"], ["H:MBA", "S"])
        self.assertIn("not a distributed coordinator", report["limitation"])

    def test_two_hosts_cannot_hold_global_token_concurrently(self) -> None:
        other = acquire(
            at="2026-10-12T00:01:00Z", owner="owner-b", operation="task-b",
            identity="incarnation-b", host="MBP",
        )
        code, report = self.invoke(scenario(acquire(), other))
        self.assertEqual(code, 1, report)
        self.assertEqual([event["result"] for event in report["events"]], ["acquired", "blocked"])
        self.assertEqual(report["events"][1]["reason"], "contended")
        self.assertEqual(report["held"], ["H:MBA", "S"])

    def test_atomic_transition_rejects_partial_or_duplicate_resource_sets(self) -> None:
        full = acquire(kind="migration_transition", repository="repo-a", connector="connector-a")
        incomplete = {**full, "requested": ["S", "H:MBA", "K:repo-a", "M:connector-a"]}
        code, report = self.invoke(scenario(incomplete))
        self.assertEqual(code, 1, report)
        self.assertEqual(report["events"][0]["reason"], "incomplete_set")
        self.assertEqual(report["held"], [])
        code, report = self.invoke(scenario({**full, "requested": full["requested"] + ["S"]}))
        self.assertEqual(code, 1, report)
        self.assertEqual(report["held"], [])
        code, report = self.invoke(scenario(full))
        self.assertEqual(code, 0, report)
        self.assertEqual(report["held"], ["H:MBA", "K:repo-a", "M:connector-a", "S", "W"])
        self.assertIsInstance(report["events"][0]["writer_fence"], int)

    def test_terminal_failure_releases_all_tokens_for_next_host(self) -> None:
        other = acquire(
            at="2026-10-12T00:03:00Z", owner="owner-b", operation="task-b",
            identity="incarnation-b", host="MBP",
        )
        code, report = self.invoke(scenario(
            acquire(kind="repository_io", repository="repo-a"),
            transition("terminal", outcome="failure"), other,
        ))
        self.assertEqual(code, 0, report)
        self.assertEqual([e["result"] for e in report["events"]], ["acquired", "released", "acquired"])
        self.assertEqual(report["held"], ["H:MBP", "S"])

    def test_wrong_incarnation_cannot_release_or_reuse_operation(self) -> None:
        code, report = self.invoke(scenario(
            acquire(),
            transition("terminal", identity="incarnation-old", outcome="success"),
            acquire(at="2026-10-12T00:03:00Z", owner="owner-a", operation="task-a",
                    identity="incarnation-old"),
        ))
        self.assertEqual(code, 1, report)
        self.assertEqual([e["result"] for e in report["events"]], ["acquired", "blocked", "blocked"])
        self.assertEqual(report["held"], ["H:MBA", "S"])

    def test_crash_and_elapsed_expiry_never_release_active_owner(self) -> None:
        other = acquire(
            at="2026-10-12T00:11:00Z", host="MBP", owner="owner-b",
            operation="task-b", identity="incarnation-b",
            expires_at="2026-10-12T00:20:00Z",
        )
        code, report = self.invoke(scenario(
            acquire(), transition("crash", at="2026-10-12T00:01:00Z"),
            transition("terminal", outcome="success"), other,
        ))
        self.assertEqual(code, 1, report)
        self.assertEqual([e["result"] for e in report["events"]],
                         ["acquired", "recorded_unknown", "blocked", "blocked"])
        self.assertEqual(report["events"][-1]["reason"], "unknown_liveness")
        self.assertEqual(report["held"], ["H:MBA", "S"])

    def test_crash_without_followup_is_not_a_success_exit(self) -> None:
        code, report = self.invoke(scenario(
            acquire(), transition("crash", at="2026-10-12T00:01:00Z"),
        ))
        self.assertEqual(code, 1, report)
        self.assertEqual([e["result"] for e in report["events"]],
                         ["acquired", "recorded_unknown"])
        self.assertEqual(report["held"], ["H:MBA", "S"])

    def test_recorded_interruption_requires_matching_synthetic_stop_witness(self) -> None:
        other = acquire(
            at="2026-10-12T00:05:00Z", host="MBP", owner="owner-b",
            operation="task-b", identity="incarnation-b",
        )
        code, report = self.invoke(scenario(
            acquire(), transition("crash", at="2026-10-12T00:01:00Z"),
            transition("interrupt", at="2026-10-12T00:02:00Z", witness=None),
            transition("interrupt", at="2026-10-12T00:04:00Z",
                       witness=stop_witness(identity="different")),
            transition("interrupt", at="2026-10-12T00:04:00Z", witness=stop_witness()), other,
        ))
        self.assertEqual(code, 1, report)  # Earlier blocked decisions remain visible.
        self.assertEqual([e["result"] for e in report["events"]],
                         ["acquired", "recorded_unknown", "blocked", "blocked", "released", "acquired"])
        self.assertEqual(report["held"], ["H:MBP", "S"])

    def test_backward_or_unknown_clock_blocks_future_acquisition(self) -> None:
        code, report = self.invoke(scenario(
            acquire(), transition("terminal", at="2026-10-12T00:02:00Z", outcome="success"),
            acquire(at="2026-10-12T00:01:00Z", owner="owner-b", operation="task-b",
                    identity="incarnation-b", host="MBP"),
        ))
        self.assertEqual(code, 1, report)
        self.assertEqual(report["events"][-1]["reason"], "clock_unknown")
        self.assertEqual(report["held"], [])
        code, report = self.invoke(scenario(
            transition("clock_unknown", at="2026-10-12T00:00:00Z"), acquire(),
        ))
        self.assertEqual(code, 1, report)
        self.assertEqual(report["events"][-1]["reason"], "clock_unknown")
        self.assertEqual(report["held"], [])

    def test_writer_requires_current_simulated_fence_and_new_owner_gets_new_epoch(self) -> None:
        code, report = self.invoke(scenario(
            acquire(kind="music_write"),
            transition("terminal", outcome="success", writer_fence=0),
            transition("terminal", outcome="success", writer_fence=1),
            acquire(at="2026-10-12T00:03:00Z", owner="owner-b", operation="task-b",
                    identity="incarnation-b", host="MBP", kind="music_write"),
        ))
        self.assertEqual(code, 1, report)
        self.assertEqual(report["events"][1]["result"], "blocked")
        self.assertEqual(report["events"][2]["result"], "released")
        self.assertEqual(report["events"][3]["writer_fence"], 2)
        self.assertEqual(report["held"], ["H:MBP", "S", "W"])

    def test_named_connector_and_repository_require_their_scoped_tokens(self) -> None:
        connector = acquire(kind="connector_change", connector="connector-one")
        repo = acquire(at="2026-10-12T00:03:00Z", owner="owner-b", operation="task-b",
                       identity="incarnation-b", host="MBP", kind="repository_io",
                       repository="repo-two")
        code, report = self.invoke(scenario(
            connector, transition("terminal", outcome="success"), repo,
        ))
        self.assertEqual(code, 0, report)
        self.assertEqual(report["events"][1]["result"], "released")
        self.assertEqual(report["held"], ["H:MBP", "K:repo-two", "S"])
        code, report = self.invoke(scenario({**connector, "requested": ["S", "H:MBA"]}))
        self.assertEqual(code, 1, report)
        self.assertEqual(report["held"], [])

    def test_unknown_owner_and_unknown_expiry_never_grant_without_fresh_identity(self) -> None:
        code, report = self.invoke(scenario(
            acquire(expires_at=None),
            acquire(at="2026-10-12T00:01:00Z", expires_at="2026-10-12T00:01:00Z"),
            acquire(at="2026-10-12T00:02:00Z"),
            transition("owner_unknown", at="2026-10-12T00:03:00Z"),
            acquire(at="2026-10-12T00:04:00Z", host="MBP", owner="owner-b",
                    operation="task-b", identity="incarnation-b"),
        ))
        self.assertEqual(code, 1, report)
        self.assertEqual([e["result"] for e in report["events"]],
                         ["blocked", "blocked", "acquired", "recorded_unknown", "blocked"])
        self.assertEqual([e["reason"] for e in report["events"][:2]],
                         ["expiry_unknown", "expiry_unknown"])
        self.assertEqual(report["events"][-1]["reason"], "unknown_liveness")
        self.assertEqual(report["held"], ["H:MBA", "S"])

    def test_expiry_alone_leaves_token_held_and_requires_recorded_stop(self) -> None:
        other = acquire(
            at="2026-10-12T00:02:00Z", host="MBP", owner="owner-b",
            operation="task-b", identity="incarnation-b",
        )
        code, report = self.invoke(scenario(
            acquire(expires_at="2026-10-12T00:01:00Z"), other,
            transition("terminal", at="2026-10-12T00:03:00Z", outcome="success"),
            transition("interrupt", at="2026-10-12T00:04:00Z", witness=stop_witness()),
        ))
        self.assertEqual(code, 1, report)
        self.assertEqual([e["result"] for e in report["events"]],
                         ["acquired", "blocked", "blocked", "released"])
        self.assertEqual(report["events"][1]["reason"], "unknown_liveness")
        self.assertEqual(report["held"], [])

    def test_future_stop_claim_and_wrong_writer_fence_do_not_clear_unknown_writer(self) -> None:
        code, report = self.invoke(scenario(
            acquire(kind="music_write"),
            transition("crash", at="2026-10-12T00:01:00Z"),
            transition("interrupt", at="2026-10-12T00:02:00Z", writer_fence=1,
                       witness=stop_witness(stopped_at="2026-10-12T00:05:00Z")),
            transition("interrupt", at="2026-10-12T00:04:00Z", writer_fence=0,
                       witness=stop_witness()),
        ))
        self.assertEqual(code, 1, report)
        self.assertEqual([e["reason"] for e in report["events"][2:]],
                         ["invalid_stop_witness", "stale_writer_fence"])
        self.assertEqual(report["held"], ["H:MBA", "S", "W"])

    def test_stop_witness_and_operation_id_are_single_use_in_simulation(self) -> None:
        code, report = self.invoke(scenario(
            acquire(), transition("crash", at="2026-10-12T00:01:00Z"),
            transition("interrupt", at="2026-10-12T00:02:00Z",
                       witness=stop_witness(stopped_at="2026-10-12T00:02:00Z")),
            acquire(at="2026-10-12T00:03:00Z", identity="incarnation-new"),
            acquire(at="2026-10-12T00:04:00Z", owner="owner-b", operation="task-b",
                    identity="incarnation-b", host="MBP"),
            transition("crash", at="2026-10-12T00:05:00Z", owner="owner-b",
                       operation="task-b", identity="incarnation-b"),
            transition("interrupt", at="2026-10-12T00:06:00Z", owner="owner-b",
                       operation="task-b", identity="incarnation-b",
                       witness=stop_witness(witness_id="witness-a", owner="owner-b",
                                            operation="task-b", identity="incarnation-b",
                                            stopped_at="2026-10-12T00:06:00Z")),
        ))
        self.assertEqual(code, 1, report)
        self.assertEqual(report["events"][3]["reason"], "operation_reused")
        self.assertEqual(report["events"][-1]["reason"], "invalid_stop_witness")
        self.assertEqual(report["held"], ["H:MBP", "S"])

    def test_excessive_json_depth_returns_unknown_without_traceback(self) -> None:
        nested = b"[" * 20_000 + b"0" + b"]" * 20_000
        code, report = self.invoke(nested)
        self.assertEqual(code, 2, report)
        self.assertEqual(report["status"], "UNKNOWN")
        self.assertNotIn("held", report)

    def test_bounded_strict_input_rejects_unknown_fields_duplicate_keys_and_nan(self) -> None:
        for bad in (
            {**scenario(acquire()), "unexpected": "ignored"},
            scenario({**acquire(), "kind": "unrecognized"}),
            scenario({**acquire(), "kind": []}),
            scenario({**acquire(), "owner": "/private/host/path"}),
            scenario({**acquire(), "host": "unrecognized"}),
            scenario({**acquire(), "at": "not-a-time"}),
            {"schema_version": True, "events": [acquire()]},
            {"schema_version": 1, "events": [acquire()] * 129},
            b'{"schema_version":1,"schema_version":1,"events":[]}',
            b'{"schema_version":1,"events":[NaN]}',
            b'{"schema_version":' + b"1" * 5_000 + b',"events":[]}',
            b" " * 65537,
        ):
            with self.subTest(bad=str(bad)[:70]):
                code, report = self.invoke(bad)
                self.assertEqual(code, 2, report)
                self.assertEqual(report["status"], "UNKNOWN")
                self.assertNotIn("held", report)


if __name__ == "__main__":
    unittest.main()
