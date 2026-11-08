"""Deterministic, fixture-only lease policy; NOT a distributed coordinator.

No host, filesystem, process, clock, or connector is inspected or changed. Input
identities, timestamps, terminal outcomes and stop witnesses are assertions from
the caller, not attestations. In particular, the integer writer fence is only a
counter in this disposable simulation and cannot fence a real writer.
"""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from typing import Any

MAX_INPUT_BYTES = 65_536
MAX_EVENTS = 128
LABEL = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}\Z")
STAMP = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\Z")
KINDS = {"heavy_io", "repository_io", "music_write", "connector_change", "migration_transition"}
COMMON = {"action", "at", "owner", "operation", "identity"}
ACQUIRE = COMMON | {"host", "kind", "repository", "connector", "requested", "expires_at"}
TRANSITION = COMMON | {"outcome", "witness", "writer_fence"}


class InvalidLease(ValueError):
    """Malformed or unknown synthetic input; never grant on parser ambiguity."""


def label(value: Any) -> str:
    if type(value) is not str or LABEL.fullmatch(value) is None:
        raise InvalidLease("invalid_identity")
    return value


def instant(value: Any) -> datetime:
    if type(value) is not str or STAMP.fullmatch(value) is None:
        raise InvalidLease("invalid_time")
    try:
        parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError as exc:
        raise InvalidLease("invalid_time") from exc
    if parsed.strftime("%Y-%m-%dT%H:%M:%SZ") != value:
        raise InvalidLease("invalid_time")
    return parsed


def exact(value: Any, fields: set[str]) -> dict[str, Any]:
    if type(value) is not dict or set(value) != fields:
        raise InvalidLease("invalid_schema")
    return value


def unique_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise InvalidLease("duplicate_field")
        result[key] = value
    return result


def reject_constant(_: str) -> None:
    raise InvalidLease("invalid_number")


def validate(payload: Any) -> list[dict[str, Any]]:
    data = exact(payload, {"schema_version", "events"})
    if type(data["schema_version"]) is not int or data["schema_version"] != 1:
        raise InvalidLease("invalid_schema")
    events = data["events"]
    if type(events) is not list or not (1 <= len(events) <= MAX_EVENTS):
        raise InvalidLease("invalid_schema")
    for event in events:
        if type(event) is not dict or event.get("action") not in (
            "acquire", "crash", "owner_unknown", "clock_unknown", "terminal", "interrupt"
        ):
            raise InvalidLease("invalid_schema")
        action = event["action"]
        exact(event, ACQUIRE if action == "acquire" else TRANSITION)
        instant(event["at"])
        for key in ("owner", "operation", "identity"):
            label(event[key])
        if action == "acquire":
            if (event["host"] not in ("MBA", "MBP")
                    or type(event["kind"]) is not str or event["kind"] not in KINDS):
                raise InvalidLease("invalid_schema")
            kind = event["kind"]
            for key, needed in (("repository", kind in ("repository_io", "migration_transition")),
                                ("connector", kind in ("connector_change", "migration_transition"))):
                if needed:
                    label(event[key])
                elif event[key] is not None:
                    raise InvalidLease("invalid_schema")
            requested = event["requested"]
            if type(requested) is not list or not (1 <= len(requested) <= 8):
                raise InvalidLease("invalid_schema")
            for resource in requested:
                if type(resource) is not str or len(resource) > 128:
                    raise InvalidLease("invalid_schema")
            if event["expires_at"] is not None:
                instant(event["expires_at"])
        else:
            fence = event["writer_fence"]
            if fence is not None and (type(fence) is not int or not 0 <= fence <= MAX_EVENTS):
                raise InvalidLease("invalid_schema")
            if action == "terminal":
                if event["outcome"] not in ("success", "failure") or event["witness"] is not None:
                    raise InvalidLease("invalid_schema")
            elif action == "interrupt":
                if event["outcome"] is not None:
                    raise InvalidLease("invalid_schema")
                witness = event["witness"]
                if witness is not None:
                    exact(witness, {"witness_id", "stopped_at", "owner", "operation", "identity"})
                    for key in ("witness_id", "owner", "operation", "identity"):
                        label(witness[key])
                    instant(witness["stopped_at"])
            elif any(event[key] is not None for key in ("outcome", "witness", "writer_fence")):
                raise InvalidLease("invalid_schema")
    return events


def required_resources(event: dict[str, Any]) -> list[str]:
    resources = ["S", f'H:{event["host"]}']
    if event["kind"] in ("repository_io", "migration_transition"):
        resources.append(f'K:{event["repository"]}')
    if event["kind"] in ("music_write", "migration_transition"):
        resources.append("W")
    if event["kind"] in ("connector_change", "migration_transition"):
        resources.append(f'M:{event["connector"]}')
    return resources


def simulate(payload: Any) -> dict[str, Any]:
    """Evaluate assertions in order, never coordinating real activity."""
    events = validate(payload)
    held: dict[str, tuple[str, str, str]] = {}
    expiries: dict[tuple[str, str, str], datetime] = {}
    acquired_at: dict[tuple[str, str, str], datetime] = {}
    fences: dict[tuple[str, str, str], int] = {}
    unknown: set[tuple[str, str, str]] = set()
    used_witnesses: set[str] = set()
    used_operations: set[tuple[str, str]] = set()
    results: list[dict[str, Any]] = []
    writer_fence = 0
    last_at: datetime | None = None
    clock_ambiguous = False

    for event in events:
        owner = (event["owner"], event["operation"], event["identity"])
        at = instant(event["at"])
        if last_at is not None and at < last_at:
            clock_ambiguous = True
        last_at = at
        action = event["action"]
        if action == "clock_unknown":
            clock_ambiguous = True
            unknown.update(expiries)
            results.append({"result": "recorded_unknown", "reason": "clock_unknown"})
            continue
        if clock_ambiguous:
            results.append({"result": "blocked", "reason": "clock_unknown"})
            continue
        unknown.update(holder for holder, expiry in expiries.items() if at >= expiry)

        if action in ("crash", "owner_unknown"):
            if owner not in held.values():
                results.append({"result": "blocked", "reason": "not_owner"})
            else:
                unknown.add(owner)
                results.append({"result": "recorded_unknown"})
            continue

        if action == "terminal":
            if owner not in held.values():
                results.append({"result": "blocked", "reason": "not_owner"})
            elif owner in unknown:
                results.append({"result": "blocked", "reason": "unknown_liveness"})
            elif event["writer_fence"] != fences.get(owner):
                results.append({"result": "blocked", "reason": "stale_writer_fence"})
            else:
                held = {resource: claimant for resource, claimant in held.items() if claimant != owner}
                del expiries[owner]
                del acquired_at[owner]
                fences.pop(owner, None)
                results.append({"result": "released", "basis": "asserted_terminal_outcome"})
            continue

        if action == "interrupt":
            witness = event["witness"]
            if owner not in held.values() or witness is None:
                results.append({"result": "blocked", "reason": "missing_stop_witness"})
                continue
            witness_owner = (witness["owner"], witness["operation"], witness["identity"])
            stopped_at = instant(witness["stopped_at"])
            witness_id = witness["witness_id"]
            if (witness_owner != owner or witness_id in used_witnesses
                    or not acquired_at[owner] <= stopped_at <= at):
                results.append({"result": "blocked", "reason": "invalid_stop_witness"})
            elif event["writer_fence"] != fences.get(owner):
                results.append({"result": "blocked", "reason": "stale_writer_fence"})
            else:
                used_witnesses.add(witness_id)
                held = {resource: claimant for resource, claimant in held.items() if claimant != owner}
                del expiries[owner]
                del acquired_at[owner]
                fences.pop(owner, None)
                unknown.discard(owner)
                results.append({"result": "released", "basis": "synthetic_stop_witness"})
            continue

        requested = event["requested"]
        required = required_resources(event)
        if len(requested) != len(required) or set(requested) != set(required):
            results.append({"result": "blocked", "reason": "incomplete_set"})
        elif (owner[0], owner[1]) in used_operations:
            results.append({"result": "blocked", "reason": "operation_reused"})
        elif any(resource in held for resource in requested):
            reason = ("unknown_liveness" if any(held[resource] in unknown
                      for resource in requested if resource in held) else "contended")
            results.append({"result": "blocked", "reason": reason})
        elif event["expires_at"] is None or instant(event["expires_at"]) <= at:
            results.append({"result": "blocked", "reason": "expiry_unknown"})
        else:
            used_operations.add((owner[0], owner[1]))
            held.update({resource: owner for resource in requested})
            expiries[owner] = instant(event["expires_at"])
            acquired_at[owner] = at
            result: dict[str, Any] = {"result": "acquired"}
            if "W" in requested:
                writer_fence += 1
                fences[owner] = writer_fence
                result["writer_fence"] = writer_fence
            results.append(result)

    return {
        "status": "SIMULATED_ONLY",
        "events": results,
        "held": sorted(held),
        "limitation": "Supplied assertions only; not a distributed coordinator or operational permission. "
                      "Synthetic stop witnesses cannot prove a real process stopped; writer fences are not enforced.",
    }


def main() -> int:
    try:
        content = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
        if len(content) > MAX_INPUT_BYTES:
            raise InvalidLease("input_too_large")
        data = json.loads(content.decode("utf-8"), object_pairs_hook=unique_pairs,
                          parse_constant=reject_constant)
        report = simulate(data)
    except (ValueError, RecursionError) as exc:
        print(json.dumps({"status": "UNKNOWN", "reason": str(exc) if isinstance(exc, InvalidLease)
                          else "invalid_json"}, sort_keys=True))
        return 2
    print(json.dumps(report, sort_keys=True))
    return 1 if any(item["result"] in ("blocked", "recorded_unknown") for item in report["events"]) else 0


if __name__ == "__main__":
    sys.exit(main())
