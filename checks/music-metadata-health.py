#!/usr/bin/env -S uv run python
"""Summarize an explicitly supplied, synthetic or private metadata evidence ledger.

This only checks the ledger's syntax and counts its claims; it does not inspect
music or independently verify the claims. No implicit library or database path
is used, and neither evidence nor identifiers are included in output.
"""

import argparse
import json
import re
import sys
from pathlib import Path

DIMENSIONS = ("recording", "release", "lyrics", "artwork")
STATES = (
    "missing",
    "verified_correct",
    "verified_wrong",
    "unknown",
    "unavailable",
    "not_applicable",
)
VERIFIED_STATES = frozenset(("verified_correct", "verified_wrong"))
KEY_PATTERN = re.compile(r"[A-Za-z0-9_-]{1,64}\Z")
LIMITATION = "Supplied reviewed claims are not independently verified."


class InvalidEvidence(ValueError):
    """Evidence does not match the accepted syntactic ledger schema."""


class PrivateArgumentParser(argparse.ArgumentParser):
    """Keep supplied paths and other private arguments out of CLI errors."""

    def error(self, message: str) -> None:
        print("error: invalid arguments", file=sys.stderr)
        raise SystemExit(2)


def unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    """Reject duplicate JSON fields at every level, including nested objects."""
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise InvalidEvidence
        result[key] = value
    return result


def reject_constant(value: str) -> None:
    """Reject non-JSON extensions such as NaN and Infinity."""
    raise InvalidEvidence


def require_fields(value: object, required: set[str], allowed: set[str]) -> dict:
    if not isinstance(value, dict) or not required <= value.keys() or value.keys() - allowed:
        raise InvalidEvidence
    return value


def validate_provenance(value: object, *, required: bool) -> None:
    if not isinstance(value, list) or (required and not value):
        raise InvalidEvidence
    labels: set[str] = set()
    for label in value:
        if not isinstance(label, str) or not label.strip():
            raise InvalidEvidence
        normalized = label.strip()
        if normalized in labels:
            raise InvalidEvidence
        labels.add(normalized)


def validate_dimension(value: object) -> str:
    detail = require_fields(value, {"state"}, {"state", "reviewed", "provenance"})
    state = detail["state"]
    if not isinstance(state, str) or state not in STATES:
        raise InvalidEvidence
    if "reviewed" in detail and not isinstance(detail["reviewed"], bool):
        raise InvalidEvidence
    verified = state in VERIFIED_STATES
    if verified and detail.get("reviewed") is not True:
        raise InvalidEvidence
    if verified or "provenance" in detail:
        validate_provenance(detail.get("provenance"), required=verified)
    return state


def summarize(evidence: object) -> dict:
    document = require_fields(evidence, {"schema_version", "items"}, {"schema_version", "items"})
    if type(document["schema_version"]) is not int or document["schema_version"] != 1:
        raise InvalidEvidence
    items = document["items"]
    if not isinstance(items, list) or not items:
        raise InvalidEvidence

    counts = {dimension: {state: 0 for state in STATES} for dimension in DIMENSIONS}
    seen_keys: set[str] = set()
    for item in items:
        entry = require_fields(item, {"key", *DIMENSIONS}, {"key", *DIMENSIONS})
        key = entry["key"]
        if not isinstance(key, str) or not KEY_PATTERN.fullmatch(key) or key in seen_keys:
            raise InvalidEvidence
        seen_keys.add(key)
        for dimension in DIMENSIONS:
            state = validate_dimension(entry[dimension])
            counts[dimension][state] += 1
    return {
        "schema_version": 1,
        "total_items": len(items),
        "counts": counts,
        "limitation": LIMITATION,
    }


def main(argv: list[str] | None = None) -> int:
    parser = PrivateArgumentParser(prog="music-metadata-health", description=__doc__)
    parser.add_argument("--evidence", required=True, metavar="PATH", type=Path)
    parser.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args(argv)

    try:
        with args.evidence.open("r", encoding="utf-8") as source:
            evidence = json.load(source, object_pairs_hook=unique_object, parse_constant=reject_constant)
        result = summarize(evidence)
    except (OSError, UnicodeError, ValueError, RecursionError):
        print("error: invalid or unreadable evidence", file=sys.stderr)
        return 2

    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False))
    else:
        print(f"Items: {result['total_items']}")
        for dimension in DIMENSIONS:
            print(f"{dimension}:")
            for state in STATES:
                print(f"  {state}: {result['counts'][dimension][state]}")
        print(f"Limitation: {LIMITATION}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
