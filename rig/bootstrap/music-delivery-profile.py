#!/usr/bin/env python3
"""Prepare an isolated byte-preserving Beets import configuration.

Paths come only from the qualified existing consumer and accepted operator.
This command never opens Beets, imports media, changes its database or activates
jobs. Run using the prepared Beets Python runtime (which already includes YAML).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import tempfile
from pathlib import Path

import yaml

MAX_CONTROL = 16 * 1024**2
SHA = re.compile(r"[0-9a-f]{64}")
POLICY = {
    "copy": True,
    "move": False,
    "write": False,
    "autotag": False,
    "link": False,
    "hardlink": False,
    "reflink": False,
    "resume": False,
    "incremental": False,
    "from_scratch": False,
    "fix_ext_inplace": False,
    "remux_mp3_in_wav": False,
    "quiet": True,
    "quiet_fallback": "asis",
    "none_rec_action": "asis",
    "default_action": "asis",
    "duplicate_action": "keep",
    "set_fields": {},
}


def need(ok: bool, reason: str) -> None:
    if not ok:
        raise ValueError(reason)


def encoded(value: object) -> bytes:
    return (
        json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + "\n"
    ).encode()


def stamp(st: os.stat_result) -> tuple:
    return st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns, st.st_ctime_ns


def read_pinned(ref: dict, limit: int = MAX_CONTROL) -> bytes:
    need(
        set(ref) == {"path", "sha256"}
        and isinstance(ref["sha256"], str)
        and SHA.fullmatch(ref["sha256"]),
        "exact_reference_required",
    )
    path = Path(ref["path"])
    before = path.lstat()
    need(
        path.is_absolute()
        and path.resolve(strict=True) == path
        and stat.S_ISREG(before.st_mode)
        and before.st_uid == os.getuid()
        and stat.S_IMODE(before.st_mode) == 0o600
        and before.st_nlink == 1
        and 0 < before.st_size <= limit,
        "private_owned_control_required",
    )
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as source:
        need(
            stamp(os.fstat(source.fileno())) == stamp(before), "opened_control_changed"
        )
        raw = source.read(limit + 1)
        need(
            stamp(os.fstat(source.fileno())) == stamp(path.lstat()) == stamp(before),
            "control_changed",
        )
    need(
        len(raw) == before.st_size and hashlib.sha256(raw).hexdigest() == ref["sha256"],
        "reference_changed",
    )
    return raw


def checked_dir(path: Path, private: bool = False) -> None:
    st = path.lstat()
    need(
        path.is_absolute()
        and path.resolve(strict=True) == path
        and stat.S_ISDIR(st.st_mode)
        and st.st_uid == os.getuid()
        and not st.st_mode & (0o077 if private else 0o022),
        "owned_real_directory_required",
    )


def database_ref(path: Path) -> dict:
    st = path.lstat()
    need(
        path.is_absolute()
        and path.resolve(strict=True) == path
        and stat.S_ISREG(st.st_mode)
        and st.st_uid == os.getuid()
        and st.st_nlink == 1
        and not st.st_mode & 0o077,
        "private_current_database_required",
    )
    h = hashlib.sha256()
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as source:
        need(stamp(os.fstat(source.fileno())) == stamp(st), "opened_database_changed")
        for block in iter(lambda: source.read(1024**2), b""):
            h.update(block)
        need(
            stamp(os.fstat(source.fileno())) == stamp(path.lstat()) == stamp(st),
            "database_changed",
        )
    return {"path": str(path), "sha256": h.hexdigest()}


def render(
    consumer_ref: dict, publication_ref: dict, operator_ref: dict, output: Path
) -> tuple[bytes, dict]:
    consumer_raw = read_pinned(consumer_ref)
    publication_raw = read_pinned(publication_ref)
    operator_raw = read_pinned(operator_ref)
    consumer, publication, operator = (
        json.loads(consumer_raw),
        json.loads(publication_raw),
        json.loads(operator_raw),
    )
    need(
        consumer.get("schema") == "mba-beets-consumer-prepared-v154"
        and consumer.get("prepared") is True
        and consumer.get("all_effective_item_paths_rebased_by_Beets_2_14") is True
        and consumer.get("raw_BLOB_paths_unchanged") is True
        and SHA.fullmatch(consumer.get("publication_sha256", "")),
        "qualified_consumer_required",
    )
    need(
        publication.get("schema") == "music-E1-publication-completed-v1"
        and publication.get("published") is True
        and publication.get("full_source_and_target_hash_comparison") is True
        and consumer["publication_sha256"] == publication_ref["sha256"]
        and publication.get("operator_contract_sha256") == operator_ref["sha256"]
        and isinstance(consumer.get("manifest_sha256"), str)
        and SHA.fullmatch(consumer["manifest_sha256"])
        and publication.get("manifest_sha256") == consumer["manifest_sha256"],
        "consumer_publication_operator_join_required",
    )
    canonical = Path(consumer["effective_directory"])
    checked_dir(canonical)
    need(
        operator.get("schema_version") == 1
        and operator.get("publication_state") == "E1"
        and operator.get("media_root") == str(canonical),
        "accepted_operator_root_mismatch",
    )
    music = Path.home() / "Music"
    need(
        not canonical.is_relative_to(music)
        and not {
            "Mobile Documents",
            "CloudStorage",
            "com~apple~CloudDocs",
        }.intersection(canonical.parts),
        "cloud_or_default_music_root_refused",
    )
    db = Path(consumer["candidate_database"])
    initial_db = database_ref(db)
    config_ref = {
        "path": consumer["candidate_config"],
        "sha256": consumer["config_sha256"],
    }
    original = yaml.safe_load(read_pinned(config_ref))
    need(isinstance(original, dict), "consumer_configuration_required")
    original_library = Path(original["library"]).expanduser()
    if not original_library.is_absolute():
        original_library = Path(config_ref["path"]).parent / original_library
    original_directory = Path(original["directory"]).expanduser()
    need(
        original_library == db and original_directory == canonical,
        "effective_consumer_paths_mismatch",
    )
    paths = original.get("paths")
    need(
        isinstance(paths, dict)
        and paths
        and all(isinstance(k, str) and isinstance(v, str) for k, v in paths.items()),
        "qualified_path_formats_required",
    )
    checked_dir(output.parent, True)
    need(
        output.is_absolute()
        and output.parent.resolve(strict=True) == output.parent
        and not output.is_relative_to(canonical)
        and not canonical.is_relative_to(output),
        "separate_profile_root_required",
    )
    profile = {
        "directory": str(canonical),
        "library": str(db),
        "plugins": [],
        "pluginpath": [],
        "include": [],
        "threaded": False,
        "import": POLICY,
        # Preserve existing qualified path conventions; this slice changes
        # delivery behavior, not library layout or the phone projection.
        "paths": paths,
    }
    raw = yaml.safe_dump(profile, sort_keys=False, allow_unicode=True).encode()
    receipt = {
        "schema": "mba-beets-delivery-profile-prepared-v1",
        "prepared": True,
        "consumer": consumer_ref,
        "publication": publication_ref,
        "operator": operator_ref,
        "initial_database": initial_db,
        "original_configuration": config_ref,
        "effective_directory": str(canonical),
        "candidate_database": str(db),
        "BEETSDIR": str(output),
        "configuration": {
            "path": str(output / "config.yaml"),
            "sha256": hashlib.sha256(raw).hexdigest(),
        },
        "normal_configuration_changed": False,
        "canonical_or_database_effects": False,
        "native_import_verified": False,
        "requires_qualified_writer_successor": True,
    }
    need(
        read_pinned(consumer_ref) == consumer_raw
        and read_pinned(publication_ref) == publication_raw
        and read_pinned(operator_ref) == operator_raw
        and database_ref(db) == initial_db,
        "inputs_changed_during_preparation",
    )
    return raw, receipt


def prepare(
    consumer_ref: dict,
    publication_ref: dict,
    operator_ref: dict,
    output: Path,
    apply: bool = False,
) -> dict:
    raw, receipt = render(consumer_ref, publication_ref, operator_ref, output)
    if not apply:
        return {
            "dry_run": True,
            "writes_performed": False,
            "canonical_or_database_effects": False,
        }
    receipt_raw = encoded(receipt)
    if output.exists() or output.is_symlink():
        checked_dir(output, True)
        need(
            {p.name for p in output.iterdir()}
            == {"config.yaml", "PREPARED.private.json"}
            and read_pinned(
                {
                    "path": str(output / "config.yaml"),
                    "sha256": hashlib.sha256(raw).hexdigest(),
                }
            )
            == raw
            and read_pinned(
                {
                    "path": str(output / "PREPARED.private.json"),
                    "sha256": hashlib.sha256(receipt_raw).hexdigest(),
                }
            )
            == receipt_raw,
            "existing_profile_changed_or_consumed_reconcile",
        )
        return {
            "prepared": True,
            "reused": True,
            "BEETSDIR": str(output),
            "canonical_or_database_effects": False,
        }
    stage = Path(tempfile.mkdtemp(prefix=".delivery-profile-", dir=output.parent))
    try:
        stage.chmod(0o700)
        for name, payload in (
            ("config.yaml", raw),
            ("PREPARED.private.json", receipt_raw),
        ):
            fd = os.open(stage / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "wb") as stream:
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
        os.rename(stage, output)
        fd = os.open(output.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    return {
        "prepared": True,
        "reused": False,
        "BEETSDIR": str(output),
        "canonical_or_database_effects": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--consumer", required=True, type=Path)
    parser.add_argument("--consumer-sha256", required=True)
    parser.add_argument("--publication", required=True, type=Path)
    parser.add_argument("--publication-sha256", required=True)
    parser.add_argument("--operator", required=True, type=Path)
    parser.add_argument("--operator-sha256", required=True)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    os.umask(0o077)
    try:
        result = prepare(
            {"path": str(args.consumer), "sha256": args.consumer_sha256},
            {"path": str(args.publication), "sha256": args.publication_sha256},
            {"path": str(args.operator), "sha256": args.operator_sha256},
            args.output_dir,
            args.apply,
        )
        print(json.dumps(result, sort_keys=True))
        return 0
    except (ValueError, OSError, KeyError, TypeError, yaml.YAMLError):
        print(
            json.dumps(
                {
                    "ok": False,
                    "status": "held_for_reconciliation",
                    "canonical_or_database_effects": False,
                }
            )
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
