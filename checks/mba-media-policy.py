"""Classify supplied relative music paths; optionally compare offline E0/E1 manifests.

No media paths are opened, scanned, hashed, copied, hydrated, or deleted. The
caller supplies kind/readability/locality assertions; this policy cannot verify
them or infer complete coverage. All classifications and comparisons are
provisional, not authorization to sync, serve, remove, or publish a library.

Classification input: {"schema_version":1,"items":[{"path":"MP3/A/song.mp3",
"kind":"file","readable":true,"local":true}, ...]}. Every eligible path
must also have supplied, readable local directory rows for all ancestors;
missing or case/Unicode-conflicting ancestry stays unresolved. Playlist rows
may supply "references" as library-root-relative paths (no '..' components).

For a non-deleting comparison use --input SOURCE --compare DESTINATION, with
both documents also containing "epoch":"E0" or "E1" and "role":"source" or
"shadow" respectively. Included files need caller-supplied "size" (bytes)
and lowercase hexadecimal "sha256"; absent metadata blocks a match. This
compares assertions, not bytes or a complete live census. "Playlists" is the
Navidrome PlaylistsPath source hint; ndignore/stignore are source hints, not
evidence of deployed settings.
"""

from __future__ import annotations

import argparse
import json
import posixpath
import re
import sys
import unicodedata
from pathlib import Path

POLICY_VERSION = "st01-v2-originals"
# One global manifest, not independently passing batches. The byte ceiling also
# caps pathological combinations of long paths and playlist references.
MAX_BYTES = 24_000_000
MAX_ITEMS = 10_000
MAX_PATH = 1_024
MAX_REFERENCES = 20_000
LIMITATION = (
    "Provisional source-hint policy; input assertions are not verified. "
    "Full eligible coverage requires user-approved policy and current source census; "
    "this report never proves either. Exclusion is not deletion authority."
)
TRANSIENT_DIRS = {"review", "staging", "quarantine", "downloading"}
TRANSIENT_NAMES = {
    ".ds_store",
    ".appledouble",
    ".spotlight-v100",
    ".trashes",
    "library.db",
    "navidrome.db",
}
TRANSIENT_SUFFIXES = (".partial", ".tmp", ".download", ".db-journal")
# Existing ingest formats plus the actual measured canonical Library roots.
AUDIO_EXTENSIONS = {".mp3", ".flac", ".m4a", ".alac", ".aac", ".wav", ".aiff", ".aif", ".ogg", ".opus"}
MUSIC_ROOTS = {"mp3", "flac", "wave", "wav", "aiff", "aac", "playlists"}
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
LYRIC_EXTENSIONS = {".lrc", ".ttml", ".elrc", ".srt"}


class InvalidInput(ValueError):
    """Invalid bounded JSON envelope or metadata."""


class QuietParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        print("error: invalid arguments", file=sys.stderr)
        raise SystemExit(2)


def unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise InvalidInput
        result[key] = value
    return result


def reject_constant(value: str) -> None:
    raise InvalidInput


def safe_path(path: str) -> bool:
    """Require literal root-relative POSIX components, without normalization."""
    return (
        0 < len(path.encode("utf-8")) <= MAX_PATH
        and not path.startswith("/")
        and not any(character in path for character in ("\\", ":"))
        and all(part not in ("", ".", "..") for part in path.split("/"))
        and all(
            ord(character) >= 32
            and ord(character) != 127
            for character in path
        )
    )


def collision_key(path: str) -> str:
    return unicodedata.normalize("NFKC", path).casefold()


def validate(document: object, *, role: str | None = None) -> list[dict[str, object]]:
    keys = {"schema_version", "items"}
    if role is not None:
        keys.update({"epoch", "role"})
    if not isinstance(document, dict) or set(document) != keys:
        raise InvalidInput
    if type(document["schema_version"]) is not int or document["schema_version"] != 1:
        raise InvalidInput
    if role is not None and (
        document["epoch"] not in ("E0", "E1") or document["role"] != role
    ):
        raise InvalidInput
    items = document["items"]
    if not isinstance(items, list) or len(items) > MAX_ITEMS:
        raise InvalidInput
    reference_count = 0
    for item in items:
        if (
            not isinstance(item, dict)
            or not {"path", "kind", "readable", "local"} <= item.keys()
        ):
            raise InvalidInput
        allowed = {"path", "kind", "readable", "local", "references"}
        if role is not None:
            allowed.update({"size", "sha256"})
        if item.keys() - allowed:
            raise InvalidInput
        if (
            not isinstance(item["path"], str)
            or len(item["path"].encode("utf-8")) > MAX_PATH
        ):
            raise InvalidInput
        if item["kind"] not in ("file", "directory", "symlink") or not isinstance(
            item["kind"], str
        ):
            raise InvalidInput
        if type(item["readable"]) is not bool or type(item["local"]) is not bool:
            raise InvalidInput
        if "size" in item and (
            item["kind"] != "file"
            or type(item["size"]) is not int
            or not 0 <= item["size"] <= 2**63 - 1
        ):
            raise InvalidInput
        if "sha256" in item and (
            item["kind"] != "file"
            or not isinstance(item["sha256"], str)
            or re.fullmatch(r"[0-9a-f]{64}", item["sha256"]) is None
        ):
            raise InvalidInput
        if "references" in item:
            if not item["path"].casefold().endswith(".m3u"):
                raise InvalidInput
            refs = item["references"]
            if not isinstance(refs, list):
                raise InvalidInput
            reference_count += len(refs)
            if reference_count > MAX_REFERENCES:
                raise InvalidInput
            if any(
                not isinstance(ref, str) or len(ref.encode("utf-8")) > MAX_PATH
                for ref in refs
            ):
                raise InvalidInput
    return items


def unresolved(
    path: str, *reasons: str, retained: str = "include"
) -> dict[str, object]:
    return {
        "path": path,
        "disposition": "unresolved",
        "served": "unresolved",
        "phone": "unresolved",
        "retained": retained,
        "reasons": list(reasons),
    }


def classified(
    path: str,
    disposition: str,
    served: str,
    phone: str,
    retained: str,
    reason: str | None = None,
) -> dict[str, object]:
    return {
        "path": path,
        "disposition": disposition,
        "served": served,
        "phone": phone,
        "retained": retained,
        "reasons": [reason] if reason else [],
    }


def copy_included(row: dict[str, object]) -> bool:
    """Preserve retained companions without claiming playback/phone eligibility."""
    return row["served"] == "include" or row["disposition"] == "retained_companion"


def initial_row(
    item: dict[str, object],
    collisions: set[str],
    items_by_key: dict[str, dict[str, object]],
) -> dict[str, object] | None:
    path = item["path"]
    if not safe_path(path):
        return unresolved(path, "unsafe_path", retained="unresolved")
    if collision_key(path) in collisions:
        return unresolved(path, "path_collision", retained="unresolved")
    if item["kind"] == "symlink":
        return unresolved(path, "symlink", retained="unresolved")
    if not item["readable"]:
        return unresolved(path, "unreadable", retained="unresolved")
    if not item["local"]:
        return unresolved(path, "cloud_placeholder", retained="unresolved")
    components = path.split("/")
    for end in range(1, len(components)):
        parent_path = "/".join(components[:end])
        key = collision_key(parent_path)
        ancestor = items_by_key.get(key)
        if (
            key in collisions
            or ancestor is None
            or ancestor["path"] != parent_path
            or ancestor["kind"] != "directory"
            or not ancestor["readable"]
            or not ancestor["local"]
        ):
            return unresolved(path, "untrusted_ancestor", retained="unresolved")
    if item["kind"] != "file":
        return unresolved(path, "not_regular_file", retained="include")
    filename = components[-1].casefold()
    if (
        (
            components[0].casefold() == "incoming"
            and len(components) > 1
            and components[1].casefold() in TRANSIENT_DIRS
        )
        or any(part.casefold() in TRANSIENT_NAMES for part in components)
        or filename.startswith("._")
        or filename.endswith(TRANSIENT_SUFFIXES)
    ):
        retained = "include" if components[0].casefold() == "incoming" else "exclude"
        return classified(
            path,
            "excluded_transient",
            "exclude",
            "exclude",
            retained,
            "explicit_transient",
        )
    if components[0].casefold() == "incoming":
        return unresolved(path, "incoming_conflict")
    if components[0].casefold() not in MUSIC_ROOTS:
        return classified(path, "retained_companion", "exclude", "exclude", "include", "outside_served_roots")
    return None


def classify(items: list[dict[str, object]]) -> dict[str, object]:
    """Use only caller-supplied metadata; never stat or resolve a media path."""
    paths: dict[str, list[int]] = {}
    unsafe_aliases: set[str] = set()
    for index, item in enumerate(items):
        path = item["path"]
        if safe_path(path):
            paths.setdefault(collision_key(path), []).append(index)
        else:
            alias = posixpath.normpath(path.replace("\\", "/"))
            if safe_path(alias):
                unsafe_aliases.add(collision_key(alias))
    collisions = {key for key, indices in paths.items() if len(indices) > 1}
    collisions.update(unsafe_aliases)
    items_by_key = {
        key: items[indices[0]] for key, indices in paths.items() if len(indices) == 1
    }
    rows: list[dict[str, object]] = []
    for item in items:
        path = item["path"]
        preliminary = initial_row(item, collisions, items_by_key)
        if preliminary is not None:
            rows.append(preliminary)
        elif Path(path).suffix.casefold() in AUDIO_EXTENSIONS:
            rows.append(
                classified(path, "eligible_original", "include", "include", "include")
            )
        else:
            rows.append(unresolved(path, "pending_classification"))
    eligible = {
        row["path"] for row in rows if row["disposition"] == "eligible_original"
    }
    track_counts: dict[str, int] = {}
    stem_counts: dict[tuple[str, str], int] = {}
    for path in eligible:
        parent, _, filename = path.rpartition("/")
        track_counts[parent] = track_counts.get(parent, 0) + 1
        stem = Path(filename).stem.casefold()
        key = (parent, stem)
        stem_counts[key] = stem_counts.get(key, 0) + 1
    for index, item in enumerate(items):
        row = rows[index]
        if row["reasons"] != ["pending_classification"]:
            continue
        path = item["path"]
        suffix = Path(path).suffix.casefold()
        if suffix == ".m3u":
            refs = item.get("references")
            if (
                isinstance(refs, list)
                and refs
                and all(safe_path(ref) and ref in eligible for ref in refs)
            ):
                rows[index] = classified(
                    path, "playlist", "include", "exclude", "include"
                )
            else:
                rows[index] = classified(path, "retained_companion", "exclude", "exclude", "include", "playlist_references_unverified")
        elif suffix in IMAGE_EXTENSIONS | LYRIC_EXTENSIONS:
            parent = path.rpartition("/")[0]
            stem = Path(path).stem.casefold()
            sibling_count = track_counts.get(parent, 0)
            if suffix in IMAGE_EXTENSIONS and sibling_count:
                rows[index] = classified(path, "intentional_sidecar", "include", "exclude", "include")
            elif suffix in LYRIC_EXTENSIONS:
                matches = stem_counts.get((parent, stem), 0)
                if matches >= 1:
                    rows[index] = classified(
                        path, "intentional_sidecar", "include", "exclude", "include"
                    )
                else:
                    rows[index] = classified(path, "retained_companion", "exclude", "exclude", "include", "sidecar_without_track")
            else:
                rows[index] = classified(path, "retained_companion", "exclude", "exclude", "include", "sidecar_without_track")
        else:
            rows[index] = classified(path, "retained_companion", "exclude", "exclude", "include", "non_audio_companion")
    return {
        "policy_version": POLICY_VERSION,
        "coverage": "unverified",
        "limitation": LIMITATION,
        "items": rows,
    }


def compare(
    source: dict[str, object], shadow: dict[str, object]
) -> dict[str, object]:
    """Compare only supplied assertions, without generating transfer/delete commands."""
    source_items = validate(source, role="source")
    shadow_items = validate(shadow, role="shadow")
    if source["epoch"] != shadow["epoch"]:
        raise InvalidInput

    def inventory(
        items: list[dict[str, object]],
    ) -> tuple[dict[str, dict[str, object]], list[str], list[str], dict[str, object]]:
        rows = classify(items)["items"]
        included: dict[str, dict[str, object]] = {}
        served: list[dict[str, object]] = []
        phone: list[dict[str, object]] = []
        sidecars: list[dict[str, object]] = []
        companions: list[dict[str, object]] = []
        unresolved_paths: list[str] = []
        excluded_paths: list[str] = []
        for item, row in zip(items, rows, strict=True):
            path = item["path"]
            if copy_included(row):
                included[path] = item
                if row["served"] == "include":
                    served.append(item)
                if row["phone"] == "include":
                    phone.append(item)
                if row["disposition"] == "intentional_sidecar":
                    sidecars.append(item)
                if row["disposition"] == "retained_companion":
                    companions.append(item)
            elif item["kind"] == "directory" and row["reasons"] == ["not_regular_file"]:
                continue
            elif row["disposition"] == "excluded_transient":
                excluded_paths.append(path)
            else:
                unresolved_paths.append(path)

        def totals(files: list[dict[str, object]]) -> dict[str, object]:
            return {
                "count": len(files),
                "bytes": (
                    sum(item["size"] for item in files)
                    if all("size" in item for item in files)
                    else None
                ),
            }

        return included, sorted(unresolved_paths), sorted(excluded_paths), {
            "copied": totals(list(included.values())),
            "served": totals(served),
            "phone": {**totals(phone), "paths": sorted(item["path"] for item in phone)},
            "retained_sidecars": {
                **totals(sidecars),
                "paths": sorted(item["path"] for item in sidecars),
            },
            "retained_companions": {
                **totals(companions),
                "paths": sorted(item["path"] for item in companions),
            },
        }

    source_set, source_unknown, _, source_totals = inventory(source_items)
    shadow_set, shadow_unknown, shadow_excluded, shadow_totals = inventory(shadow_items)
    missing = sorted(source_set.keys() - shadow_set.keys())
    extra = sorted(shadow_set.keys() - source_set.keys()) + shadow_excluded
    extra.sort()
    missing_metadata: list[str] = []
    changed: list[str] = []
    for path in sorted(source_set.keys() & shadow_set.keys()):
        left, right = source_set[path], shadow_set[path]
        has_metadata = all(
            field in item for item in (left, right) for field in ("size", "sha256")
        )
        if not has_metadata:
            missing_metadata.append(path)
        if (has_metadata and (left["size"], left["sha256"]) !=
                (right["size"], right["sha256"])) or left.get("references") != right.get("references"):
            changed.append(path)
    for path in missing + extra:
        item = source_set.get(path, shadow_set.get(path))
        if item is not None and ("size" not in item or "sha256" not in item):
            missing_metadata.append(path)
    missing_metadata.sort()
    blockers = [
        name
        for name, present in (
            ("empty_source", not source_set),
            ("unresolved_source", bool(source_unknown)),
            ("unresolved_shadow", bool(shadow_unknown)),
            ("missing_shadow", bool(missing)),
            ("extra_shadow", bool(extra)),
            ("changed", bool(changed)),
            ("missing_metadata", bool(missing_metadata)),
        )
        if present
    ]
    return {
        "policy_version": POLICY_VERSION,
        "epoch": source["epoch"],
        "operation": "compare_only",
        "status": "blocked" if blockers else "matching_assertions",
        "blockers": blockers,
        "coverage": "unverified",
        "limitation": LIMITATION,
        "source": source_totals,
        "shadow": shadow_totals,
        "unresolved_source": source_unknown,
        "unresolved_shadow": shadow_unknown,
        "missing_shadow": missing,
        "extra_shadow": extra,
        "changed": changed,
        "missing_metadata": missing_metadata,
    }


def read_document(path: Path) -> object:
    with path.open("rb") as stream:
        payload = stream.read(MAX_BYTES + 1)
    if len(payload) > MAX_BYTES:
        raise InvalidInput
    return json.loads(
        payload.decode("utf-8"),
        object_pairs_hook=unique_object,
        parse_constant=reject_constant,
    )


def main(argv: list[str] | None = None) -> int:
    parser = QuietParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, metavar="JSON_FILE")
    parser.add_argument("--compare", type=Path, metavar="SHADOW_JSON")
    args = parser.parse_args(argv)
    try:
        source = read_document(args.input)
        if args.compare is not None:
            shadow = read_document(args.compare)
            result = compare(source, shadow)
        else:
            result = classify(validate(source))
    except (OSError, UnicodeError, ValueError, RecursionError, TypeError):
        print("error: invalid input", file=sys.stderr)
        return 2
    print(json.dumps(result, ensure_ascii=False))
    return 1 if args.compare is not None and result["status"] == "blocked" else 0


if __name__ == "__main__":
    raise SystemExit(main())
