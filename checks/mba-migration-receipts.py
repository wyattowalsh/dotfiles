"""Offline, read-only comparison of caller-supplied migration receipts.

Read a bounded schema_version=1 JSON envelope from stdin with scope, receipts,
requirements, instance_sets, and decisions. Evaluate under an explicit --now UTC
instant. Each receipt must have an exact shared host/endpoint/APFS volume-container,
config, music epoch/manifest, source/installed hash and repository scope; a
normalized status, observation and expiry; opaque operation/target/recipient/budget
IDs; approval-reference metadata scoped to those IDs; checks, rollback readiness
and invalidation markers. Requirements form a bounded AND-DAG. A requirement's
instances=["*"] means *all IDs in its explicitly supplied instance_sets entry*,
not an independent census. Conditional nodes require both pass and fail arms
plus an explicit decision. A fail outcome never supplies capacity.

All IDs, timestamps, hashes, status, approval decisions, selected instance sets,
checks and rollback readiness are UNVERIFIED input assertions. A reported
"matching_assertions" and process exit 0 are only an offline schema/join result;
not host attestation, production PASS, evidence of actual permission or authority
to dispatch any operation. This module never opens host, media or repository paths.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timedelta, timezone

SCHEMA_VERSION = 1
MAX_INPUT_BYTES = 65_536
TOP_FIELDS = {"schema_version", "scope", "receipts", "requirements", "instance_sets", "decisions"}
SCOPE_FIELDS = {"host_id", "endpoint_id", "volume_id", "container_id", "config_sha256",
                "epoch_id", "manifest_sha256", "source_sha256", "installed_sha256", "repository_id"}
HASH_FIELDS = {"config_sha256", "manifest_sha256", "source_sha256", "installed_sha256"}
RECEIPT_FIELDS = {"leaf_id", "instance_id", "status", "coverage", "observed_at",
                  "expires_at", "scope", "operation_id", "target_ids", "recipient_id",
                  "budget_id", "approval", "checks", "rollback", "invalidations"}
STATUSES = {"not_started", "verified", "partial", "blocked", "failed"}
COVERAGES = {"source_only", "local_observation_only", "production_claimed"}
INVALIDATION_KINDS = {"new_write", "mount_change", "app_update", "credential_rotation",
                      "elapsed_fence", "user_edit", "source_changed", "installed_changed",
                      "repository_changed"}
MAX_RECEIPTS = 256
MAX_AGE = timedelta(hours=24)
APPROVAL_FIELDS = {"reference_id", "decision", "operation_id", "target_ids", "host_id",
                   "endpoint_id", "epoch_id", "recipient_id", "budget_id", "scope"}


class InvalidReceipt(ValueError):
    """Invalid receipt envelope or supplied dependency graph."""


def fields(raw: object, names: set[str]) -> dict:
    if not isinstance(raw, dict) or set(raw) != names:
        raise InvalidReceipt("invalid_schema")
    return raw


def unique_pairs(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise InvalidReceipt("duplicate_field")
        result[key] = value
    return result


def invalid_number(_: str) -> None:
    raise InvalidReceipt("invalid_number")


def identity(raw: object) -> str:
    if (not isinstance(raw, str) or not 1 <= len(raw) <= 128
            or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.:-]*", raw) is None):
        raise InvalidReceipt("invalid_identity")
    return raw


def digest(raw: object) -> str:
    if not isinstance(raw, str) or re.fullmatch(r"[0-9a-f]{64}", raw) is None:
        raise InvalidReceipt("invalid_hash")
    return raw


def timestamp(raw: object) -> datetime:
    if not isinstance(raw, str) or re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", raw) is None:
        raise InvalidReceipt("invalid_timestamp")
    try:
        value = datetime.strptime(raw, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError as exc:
        raise InvalidReceipt("invalid_timestamp") from exc
    if value.strftime("%Y-%m-%dT%H:%M:%SZ") != raw:
        raise InvalidReceipt("invalid_timestamp")
    return value


def scope(raw: object) -> dict:
    result = fields(raw, SCOPE_FIELDS)
    for name, value in result.items():
        (digest if name in HASH_FIELDS else identity)(value)
    return result


def bounded_list(raw: object, limit: int, *, nonempty: bool = False) -> list:
    if not isinstance(raw, list) or len(raw) > limit or (nonempty and not raw):
        raise InvalidReceipt("invalid_schema")
    return raw


def join_requirements(data: dict, satisfied: dict[tuple[str, str], bool]) -> set[str]:
    """Validate a bounded DAG and AND-join every explicitly required instance."""
    requirements = bounded_list(data["requirements"], MAX_RECEIPTS, nonempty=True)
    instance_sets = bounded_list(data["instance_sets"], MAX_RECEIPTS)
    selected: dict[str, set[str]] = {}
    for raw_set in instance_sets:
        group = fields(raw_set, {"leaf_id", "selected"})
        leaf = identity(group["leaf_id"])
        instances = bounded_list(group["selected"], 32, nonempty=True)
        for instance in instances:
            identity(instance)
        if leaf in selected or len(set(instances)) != len(instances):
            raise InvalidReceipt("duplicate_instance")
        selected[leaf] = set(instances)
    nodes: dict[str, dict] = {}
    for raw_node in requirements:
        node = fields(raw_node, {"id", "leaf_id", "instances", "depends_on", "condition"})
        name = identity(node["id"])
        identity(node["leaf_id"])
        instances = bounded_list(node["instances"], 32, nonempty=True)
        for instance in instances:
            if instance != "*":
                identity(instance)
        if len(set(instances)) != len(instances) or ("*" in instances and len(instances) != 1):
            raise InvalidReceipt("duplicate_instance")
        dependencies = bounded_list(node["depends_on"], MAX_RECEIPTS)
        for dependency in dependencies:
            identity(dependency)
        if len(set(dependencies)) != len(dependencies):
            raise InvalidReceipt("duplicate_dependency")
        if node["condition"] is not None:
            condition = fields(node["condition"], {"id", "when"})
            identity(condition["id"])
            if not isinstance(condition["when"], str) or condition["when"] not in ("pass", "fail"):
                raise InvalidReceipt("invalid_condition")
        if name in nodes:
            raise InvalidReceipt("duplicate_requirement")
        nodes[name] = node
    for node in nodes.values():
        if any(dependency not in nodes for dependency in node["depends_on"]):
            raise InvalidReceipt("missing_dependency")
    if set(selected) - {node["leaf_id"] for node in nodes.values() if node["instances"] == ["*"]}:
        raise InvalidReceipt("unreferenced_instance_set")
    # Iterative DFS keeps a malformed graph bounded without relying on recursion depth.
    state: dict[str, int] = {}
    for root in nodes:
        stack = [(root, False)]
        while stack:
            name, finished = stack.pop()
            if finished:
                state[name] = 2
                continue
            if state.get(name) == 2:
                continue
            if state.get(name) == 1:
                raise InvalidReceipt("cyclic_dependency")
            state[name] = 1
            stack.append((name, True))
            stack.extend((dependency, False) for dependency in nodes[name]["depends_on"])
    decisions = bounded_list(data["decisions"], MAX_RECEIPTS)
    outcomes: dict[str, str] = {}
    for raw_decision in decisions:
        decision = fields(raw_decision, {"id", "outcome"})
        decision_id = identity(decision["id"])
        if decision_id in outcomes:
            raise InvalidReceipt("duplicate_decision")
        if not isinstance(decision["outcome"], str) or decision["outcome"] not in ("pass", "fail", "unknown"):
            raise InvalidReceipt("invalid_decision")
        outcomes[decision_id] = decision["outcome"]
    branches: dict[str, set[str]] = {}
    for node in nodes.values():
        if node["condition"] is not None:
            condition = node["condition"]
            branches.setdefault(condition["id"], set()).add(condition["when"])
    if set(outcomes) - set(branches):
        raise InvalidReceipt("unreferenced_decision")
    reasons: set[str] = set()
    if any(arms != {"pass", "fail"} for arms in branches.values()):
        reasons.add("conditional_branch_gap")
    if any(outcomes.get(condition_id, "unknown") == "unknown" for condition_id in branches):
        reasons.add("conditional_unknown")
    if "fail" in outcomes.values():
        reasons.add("conditional_failed")
    active = {name for name, node in nodes.items()
              if node["condition"] is None or
              node["condition"]["when"] == outcomes.get(node["condition"]["id"])}
    required_receipts: set[tuple[str, str]] = set()
    node_satisfied: dict[str, bool] = {}
    # Topological order is not needed: each node can check the supplied receipts of
    # its parents, and inactive parents are explicitly rejected.
    for name in active:
        node = nodes[name]
        instances = node["instances"]
        if instances == ["*"]:
            if node["leaf_id"] not in selected:
                reasons.add("missing_instance_set")
                node_satisfied[name] = False
                continue
            instances = selected[node["leaf_id"]]
        complete = True
        for instance in instances:
            key = (node["leaf_id"], instance)
            if key in required_receipts:
                raise InvalidReceipt("duplicate_instance")
            required_receipts.add(key)
            if key not in satisfied:
                reasons.add("missing_receipt")
                complete = False
            elif not satisfied[key]:
                complete = False
        node_satisfied[name] = complete
    for name in active:
        for dependency in nodes[name]["depends_on"]:
            if dependency not in active:
                reasons.add("dependency_inactive")
            elif not node_satisfied.get(dependency, False):
                reasons.add("unsatisfied_dependency")
    if set(satisfied) - required_receipts:
        reasons.add("unrequired_receipt")
    if not active:
        reasons.add("no_active_requirements")
    return reasons


def evaluate(raw: object, *, now: datetime) -> dict[str, object]:
    """Compare supplied assertions under a caller-injected UTC clock; never host proof."""
    if now.tzinfo is None or now.utcoffset() != timedelta(0):
        raise InvalidReceipt("invalid_timestamp")
    data = fields(raw, TOP_FIELDS)
    if type(data["schema_version"]) is not int or data["schema_version"] != SCHEMA_VERSION:
        raise InvalidReceipt("invalid_schema")
    expected_scope = scope(data["scope"])
    receipts = bounded_list(data["receipts"], MAX_RECEIPTS)
    reasons: set[str] = set()
    satisfied: dict[tuple[str, str], bool] = {}
    for raw_receipt in receipts:
        item = fields(raw_receipt, RECEIPT_FIELDS)
        key = (identity(item["leaf_id"]), identity(item["instance_id"]))
        if key in satisfied:
            raise InvalidReceipt("duplicate_receipt")
        item_reasons: set[str] = set()
        actual_scope = scope(item["scope"])
        if actual_scope != expected_scope:
            item_reasons.add("scope_mismatch")
        if not isinstance(item["status"], str) or item["status"] not in STATUSES:
            raise InvalidReceipt("invalid_status")
        if item["status"] != "verified":
            item_reasons.add("unsatisfied_status")
        if not isinstance(item["coverage"], str) or item["coverage"] not in COVERAGES:
            raise InvalidReceipt("invalid_coverage")
        observed = timestamp(item["observed_at"])
        expiry = timestamp(item["expires_at"])
        if observed > now:
            item_reasons.add("future_observation")
        if expiry <= now:
            item_reasons.add("expired_receipt")
        if expiry <= observed or expiry - observed > MAX_AGE or now - observed > MAX_AGE:
            item_reasons.add("stale_receipt")
        invalidations = bounded_list(item["invalidations"], 16)
        if any(not isinstance(marker, str) or marker not in INVALIDATION_KINDS
               for marker in invalidations) or len(invalidations) != len(set(invalidations)):
            raise InvalidReceipt("invalid_invalidation")
        if invalidations:
            item_reasons.add("invalidated_receipt")
        identity(item["operation_id"])
        identity(item["recipient_id"])
        identity(item["budget_id"])
        targets = bounded_list(item["target_ids"], 32, nonempty=True)
        for target in targets:
            identity(target)
        if len(set(targets)) != len(targets):
            raise InvalidReceipt("duplicate_target")
        approval = fields(item["approval"], APPROVAL_FIELDS)
        for name in APPROVAL_FIELDS - {"decision", "target_ids", "scope"}:
            identity(approval[name])
        approval_scope = scope(approval["scope"])
        approval_targets = bounded_list(approval["target_ids"], 32, nonempty=True)
        for target in approval_targets:
            identity(target)
        if len(set(approval_targets)) != len(approval_targets):
            raise InvalidReceipt("duplicate_target")
        if approval["decision"] not in ("granted", "denied", "pending") or not isinstance(approval["decision"], str):
            raise InvalidReceipt("invalid_approval")
        if approval["decision"] != "granted":
            item_reasons.add("approval_denied_or_pending")
        exact = {"operation_id": item["operation_id"], "target_ids": targets,
                 "host_id": actual_scope["host_id"], "endpoint_id": actual_scope["endpoint_id"],
                 "epoch_id": actual_scope["epoch_id"], "recipient_id": item["recipient_id"],
                 "budget_id": item["budget_id"]}
        if approval_scope != actual_scope or any(approval[key] != value for key, value in exact.items()):
            item_reasons.add("approval_scope_mismatch")
        checks = bounded_list(item["checks"], 32, nonempty=True)
        names: set[str] = set()
        for raw_check in checks:
            check = fields(raw_check, {"name", "result"})
            name = identity(check["name"])
            if name in names:
                raise InvalidReceipt("duplicate_check")
            names.add(name)
            if check["result"] not in ("pass", "fail", "unknown") or not isinstance(check["result"], str):
                raise InvalidReceipt("invalid_check")
            if check["result"] != "pass":
                item_reasons.add("check_unsatisfied")
        rollback = fields(item["rollback"], {"reference_id", "ready"})
        identity(rollback["reference_id"])
        if type(rollback["ready"]) is not bool:
            raise InvalidReceipt("invalid_rollback")
        if not rollback["ready"]:
            item_reasons.add("rollback_not_ready")
        satisfied[key] = not item_reasons
        reasons.update(item_reasons)
    reasons.update(join_requirements(data, satisfied))
    return {
        "schema_version": SCHEMA_VERSION,
        "status": "blocked" if reasons else "matching_assertions",
        "coverage": "unverified",
        "operation_authorized": False,
        "reasons": sorted(reasons),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--now", required=True, help="Synthetic UTC evaluation instant")
    args = parser.parse_args(argv)
    try:
        now = timestamp(args.now)
        payload = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
        if len(payload) > MAX_INPUT_BYTES:
            raise InvalidReceipt("input_too_large")
        try:
            raw = json.loads(payload.decode("utf-8"), object_pairs_hook=unique_pairs,
                             parse_constant=invalid_number, parse_float=invalid_number)
        except (ValueError, UnicodeError, RecursionError) as exc:
            if isinstance(exc, InvalidReceipt):
                raise
            raise InvalidReceipt("invalid_json") from exc
        result = evaluate(raw, now=now)
    except (ValueError, UnicodeError, RecursionError) as exc:
        reason = str(exc) if isinstance(exc, InvalidReceipt) else "invalid_timestamp"
        result = {"schema_version": SCHEMA_VERSION, "status": "unknown",
                  "coverage": "unverified", "operation_authorized": False,
                  "reason": reason}
        print(json.dumps(result))
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0 if result["status"] == "matching_assertions" else 1


if __name__ == "__main__":
    raise SystemExit(main())
