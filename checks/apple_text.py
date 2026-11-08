"""Apple Text Replacement registry, overlay, merge, and staging helpers."""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Final, Literal

REPO_ROOT: Final = Path(__file__).resolve().parent.parent
SCHEMA_VERSION: Final = 2
OVERLAY_VERSIONS: Final = frozenset({1, 2})
REGISTRY_RELATIVE: Final = Path("rig") / "home" / "private_dot_config" / "apple-text" / "expansions.json"
DEFAULT_OVERLAY: Final = Path.home() / ".config" / "apple-text" / "expansions.local.json"
DEFAULT_STATE: Final = Path.home() / ".local" / "state" / "dotfiles" / "apple-text"
RETAINED_EXCEPTIONS: Final = frozenset({"==+", "myEn", "w4w"})
COMPACT_TRIGGER_RE: Final = re.compile(r"^;[a-z]{2,5}$")
HELP_TRIGGER_RE: Final = re.compile(r"^;help$")
REFERENCE_TRIGGER_RE: Final = re.compile(r"^;h[1-9][0-9]*$")
FORBIDDEN_TRIGGERS: Final = frozenset({";", ";;", "$", "x", "jj"})
HELP_GROUP_ORDER: Final = ("AI", "CODE", "MESSAGES", "PERSONAL", "FORMATTING", "KEPT")
PRIVATE_FILE_MODE: Final = 0o600
PRIVATE_DIR_MODE: Final = 0o700
INVISIBLE_RE: Final = re.compile(r"[​-‏‪-‮⁠-⁯﻿]")
PSEUDO_DYNAMIC_RE: Final = re.compile(
    r"\{\{[^}]+\}\}|\$clipboard|%date%|\$\{[^}]+\}|%\w+%",
    re.IGNORECASE,
)
SECRET_RE: Final = re.compile(
    r"(?i)(sk-[a-z0-9]{16,}|api[_-]?key\s*[:=]|begin (rsa |openssh )?private key|ghp_[a-zA-Z0-9]{20,})",
)
TRIGGER_KEY_CANDIDATES: Final = ("shortcut", "replace")
PHRASE_KEY_CANDIDATES: Final = ("phrase", "with")
PlanOpKind = Literal[
    "ADD",
    "UPDATE",
    "MIGRATE",
    "RETIRE",
    "PRESERVE",
    "PRIVATE",
    "UNCHANGED",
    "CONFLICT",
    "UNRESOLVED",
]


class AppleTextError(ValueError):
    """Raised when Apple text-expansion input or state is invalid."""


@dataclass(frozen=True)
class Expansion:
    ident: str
    trigger: str
    category: str
    enabled: bool
    multiline: bool
    sensitivity: str
    shell_safe: bool
    surfaces: tuple[str, ...]
    replaces: tuple[str, ...]
    phrase: str | None = None
    local_value_key: str | None = None
    duplicate_phrase_justification: str | None = None
    label: str = ""
    help_group: str = ""
    kind: str = "literal"
    legacy_exception: bool = False
    predecessor_phrases: tuple[tuple[str, str], ...] = ()

    @property
    def is_private(self) -> bool:
        return self.sensitivity == "private" or self.local_value_key is not None


@dataclass(frozen=True)
class RetiredTrigger:
    trigger: str
    reason: str
    replaced_by: str | None = None


@dataclass(frozen=True)
class ReservedTrigger:
    trigger: str
    reason: str
    provenance: str


@dataclass(frozen=True)
class GeneratedHelp:
    ident: str
    trigger: str
    label: str
    page_budget: int
    initial_membership: tuple[tuple[str, tuple[str, ...]], ...]


@dataclass(frozen=True)
class Catalog:
    version: int
    expansions: list[Expansion]
    retired: list[RetiredTrigger]
    reserved: list[ReservedTrigger]
    generated_help: GeneratedHelp


@dataclass(frozen=True)
class Overlay:
    version: int
    values: dict[str, str]
    overrides: dict[str, Any]


@dataclass(frozen=True)
class PlanOp:
    kind: PlanOpKind
    trigger: str
    detail: str = ""


@dataclass
class MergePlan:
    operations: list[PlanOp] = field(default_factory=list)
    merged: list[dict[str, Any]] = field(default_factory=list)
    additions: list[dict[str, Any]] = field(default_factory=list)
    schema_id: str = "shortcut-phrase"
    wrapper_metadata: dict[str, Any] = field(default_factory=dict)
    reference_manifest: dict[str, Any] | None = None
    reference_pages: list[dict[str, Any]] = field(default_factory=list)
    preserved_unrelated: int = 0
    private_summaries: list[str] = field(default_factory=list)
    complete: bool = True

    def add(self, kind: PlanOpKind, trigger: str, detail: str = "") -> None:
        self.operations.append(PlanOp(kind, trigger, detail))


def _repo_root(root: Path | None = None) -> Path:
    if root is not None:
        return root
    return REPO_ROOT


def registry_path(root: Path | None = None) -> Path:
    return _repo_root(root) / REGISTRY_RELATIVE


def default_overlay_path() -> Path:
    override = os.environ.get("DOTFILES_APPLE_TEXT_OVERLAY")
    if override:
        return Path(override)
    return DEFAULT_OVERLAY


def default_state_path() -> Path:
    override = os.environ.get("DOTFILES_APPLE_TEXT_STATE")
    if override:
        return Path(override)
    return DEFAULT_STATE


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise AppleTextError(f"invalid JSON in {path}: {exc}") from exc


def _expansion_from_mapping(raw: dict[str, Any]) -> Expansion:
    unknown = sorted(set(raw) - EXPANSION_FIELDS)
    if unknown:
        raise AppleTextError("unknown expansion fields: " + ", ".join(unknown))
    ident = _require_str(raw, "id")
    if not re.fullmatch(r"[a-z][a-z0-9.-]*", ident):
        raise AppleTextError("invalid expansion id")
    trigger = _require_str(raw, "trigger")
    phrase = raw.get("phrase")
    local_key = raw.get("local_value_key")
    surfaces = raw.get("surfaces")
    replaces = raw.get("replaces")
    if not isinstance(surfaces, list) or not surfaces or not all(isinstance(item, str) for item in surfaces):
        raise AppleTextError(f"{ident}: surfaces must be a non-empty string list")
    if len(surfaces) != len(set(surfaces)):
        raise AppleTextError(f"{ident}: surfaces must be unique")
    if not isinstance(replaces, list) or not all(isinstance(item, str) and item for item in replaces):
        raise AppleTextError(f"{ident}: replaces must be a list of non-empty strings")
    predecessors = raw.get("predecessor_phrases", [])
    if not isinstance(predecessors, list):
        raise AppleTextError(f"{ident}: predecessor_phrases must be a list")
    parsed_predecessors: list[tuple[str, str]] = []
    for item in predecessors:
        if not isinstance(item, dict):
            raise AppleTextError(f"{ident}: predecessor phrase must be an object")
        _check_fields(item, {"trigger", "phrase"}, f"{ident} predecessor phrase")
        parsed_predecessors.append((_require_str(item, "trigger"), _require_str(item, "phrase")))
    kind = _require_str(raw, "kind")
    category = _require_str(raw, "category")
    sensitivity = _require_str(raw, "sensitivity")
    if kind not in KINDS:
        raise AppleTextError(f"{ident}: invalid kind")
    if category not in CATEGORIES:
        raise AppleTextError(f"{ident}: invalid category")
    if sensitivity not in SENSITIVITIES:
        raise AppleTextError(f"{ident}: invalid sensitivity")
    if any(item not in SURFACES for item in surfaces):
        raise AppleTextError(f"{ident}: invalid surface")
    if phrase is not None and not isinstance(phrase, str):
        raise AppleTextError(f"{ident}: phrase must be a string")
    if local_key is not None and (not isinstance(local_key, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", local_key)):
        raise AppleTextError(f"{ident}: local_value_key must be a lowercase key")
    if "duplicate_phrase_justification" in raw and (not isinstance(raw["duplicate_phrase_justification"], str) or not raw["duplicate_phrase_justification"]):
        raise AppleTextError(f"{ident}: duplicate_phrase_justification must be a non-empty string")
    return Expansion(
        ident=ident,
        trigger=trigger,
        category=category,
        enabled=_require_bool(raw, "enabled"),
        multiline=_require_bool(raw, "multiline"),
        sensitivity=sensitivity,
        shell_safe=_require_bool(raw, "shell_safe"),
        surfaces=tuple(surfaces),
        replaces=tuple(replaces),
        phrase=phrase if isinstance(phrase, str) else None,
        local_value_key=local_key,
        duplicate_phrase_justification=raw.get("duplicate_phrase_justification"),
        label=_require_str(raw, "label"),
        help_group=_require_str(raw, "help_group"),
        kind=kind,
        legacy_exception=_require_bool(raw, "legacy_exception"),
        predecessor_phrases=tuple(parsed_predecessors),
    )


def _check_fields(raw: dict[str, Any], allowed: set[str], name: str) -> None:
    unknown = sorted(set(raw) - allowed)
    if unknown:
        raise AppleTextError(f"unknown {name} fields: {', '.join(unknown)}")


def _require_str(raw: dict[str, Any], key: str) -> str:
    value = raw.get(key)
    if not isinstance(value, str) or not value:
        raise AppleTextError(f"field {key!r} must be a non-empty string")
    return value


def _require_bool(raw: dict[str, Any], key: str) -> bool:
    if key not in raw:
        raise AppleTextError(f"field {key!r} is required")
    value = raw[key]
    if type(value) is not bool:
        raise AppleTextError(f"field {key!r} must be a boolean")
    return value


EXPANSION_FIELDS: Final = frozenset(
    {
        "id",
        "trigger",
        "phrase",
        "local_value_key",
        "category",
        "enabled",
        "multiline",
        "sensitivity",
        "shell_safe",
        "surfaces",
        "replaces",
        "label",
        "help_group",
        "kind",
        "legacy_exception",
        "predecessor_phrases",
        "duplicate_phrase_justification",
    }
)
KINDS: Final = frozenset({"literal", "instruction", "editable-template"})
CATEGORIES: Final = frozenset({"identity", "message", "ai", "engineering", "markdown", "symbol"})
SENSITIVITIES: Final = frozenset({"public", "private"})
SURFACES: Final = frozenset({"text-replacement", "shortcut-library", "expand-anywhere"})


def load_catalog(path: Path | None = None, *, root: Path | None = None) -> Catalog:
    target = path or registry_path(root)
    data = _read_json(target)
    if not isinstance(data, dict):
        raise AppleTextError("registry must contain a JSON object")
    _check_fields(data, {"$schema", "version", "expansions", "retired_triggers", "reserved_triggers", "generated_help"}, "registry")
    if "$schema" in data and not isinstance(data["$schema"], str):
        raise AppleTextError("registry $schema must be a string")
    version = data.get("version")
    if type(version) is not int or version != SCHEMA_VERSION:
        raise AppleTextError(f"unsupported registry version: {version}")
    raw_expansions = data.get("expansions")
    raw_retired = data.get("retired_triggers")
    raw_reserved = data.get("reserved_triggers")
    raw_help = data.get("generated_help")
    if not isinstance(raw_expansions, list) or not raw_expansions:
        raise AppleTextError("expansions must be a non-empty array")
    if not isinstance(raw_retired, list):
        raise AppleTextError("retired_triggers must be an array")
    if not isinstance(raw_reserved, list) or not raw_reserved:
        raise AppleTextError("reserved_triggers must be a non-empty array")
    if not isinstance(raw_help, dict):
        raise AppleTextError("generated_help must be an object")
    _check_fields(raw_help, {"id", "trigger", "label", "page_budget", "initial_membership"}, "generated_help")
    if raw_help.get("trigger") != ";help":
        raise AppleTextError("generated_help.trigger must be ;help")
    expansions = [_expansion_from_mapping(item) for item in raw_expansions if isinstance(item, dict)]
    if len(expansions) != len(raw_expansions):
        raise AppleTextError("every expansion must be an object")
    retired: list[RetiredTrigger] = []
    for item in raw_retired:
        if not isinstance(item, dict):
            raise AppleTextError("every retired trigger must be an object")
        _check_fields(item, {"trigger", "reason", "replaced_by"}, "retired trigger")
        if "replaced_by" in item and (not isinstance(item["replaced_by"], str) or not item["replaced_by"]):
            raise AppleTextError("retired trigger replaced_by must be a non-empty string")
        retired.append(
            RetiredTrigger(
                trigger=_require_str(item, "trigger"),
                reason=_require_str(item, "reason"),
                replaced_by=item.get("replaced_by"),
            )
        )
    reserved: list[ReservedTrigger] = []
    for item in raw_reserved:
        if not isinstance(item, dict):
            raise AppleTextError("every reserved trigger must be an object")
        _check_fields(item, {"trigger", "reason", "provenance"}, "reserved trigger")
        reserved.append(
            ReservedTrigger(
                trigger=_require_str(item, "trigger"),
                reason=_require_str(item, "reason"),
                provenance=_require_str(item, "provenance"),
            )
        )
    membership_raw = raw_help.get("initial_membership")
    if not isinstance(membership_raw, dict):
        raise AppleTextError("generated_help.initial_membership must be an object")
    membership: list[tuple[str, tuple[str, ...]]] = []
    for trigger, entries in membership_raw.items():
        if not isinstance(trigger, str) or not REFERENCE_TRIGGER_RE.fullmatch(trigger) or not isinstance(entries, list):
            raise AppleTextError("generated_help membership is malformed")
        if not all(isinstance(entry, str) for entry in entries):
            raise AppleTextError("generated_help membership entries must be strings")
        membership.append((trigger, tuple(entries)))
    budget = raw_help.get("page_budget")
    if type(budget) is not int or budget < 1:
        raise AppleTextError("generated_help.page_budget must be a positive integer")
    if not re.fullmatch(r"[a-z][a-z0-9.-]*", _require_str(raw_help, "id")):
        raise AppleTextError("invalid generated_help id")
    generated = GeneratedHelp(
        ident=_require_str(raw_help, "id"),
        trigger=_require_str(raw_help, "trigger"),
        label=_require_str(raw_help, "label"),
        page_budget=budget,
        initial_membership=tuple(membership),
    )
    return Catalog(version=version, expansions=expansions, retired=retired, reserved=reserved, generated_help=generated)


def load_registry(
    path: Path | None = None, *, root: Path | None = None
) -> tuple[list[Expansion], list[RetiredTrigger]]:
    catalog = load_catalog(path, root=root)
    return catalog.expansions, catalog.retired


def load_overlay(path: Path | None = None) -> Overlay | None:
    target = path or default_overlay_path()
    if not target.is_file():
        return None
    data = _read_json(target)
    if not isinstance(data, dict):
        raise AppleTextError(f"{target} must contain a JSON object")
    _check_fields(data, {"version", "values", "overrides"}, "overlay")
    values_raw = data.get("values", {})
    overrides = data.get("overrides", {})
    if not isinstance(values_raw, dict) or not isinstance(overrides, dict):
        raise AppleTextError("overlay values and overrides must be objects")
    values: dict[str, str] = {}
    for key, value in values_raw.items():
        if not isinstance(key, str) or not isinstance(value, str):
            raise AppleTextError("overlay values must be string to string")
        values[key] = value
    version = data.get("version", 1)
    if type(version) is not int or version not in OVERLAY_VERSIONS:
        raise AppleTextError(f"unsupported overlay version: {version}")
    return Overlay(version=int(version), values=values, overrides=overrides)


def write_overlay(overlay: Overlay, path: Path | None = None) -> Path:
    target = path or default_overlay_path()
    target.parent.mkdir(parents=True, exist_ok=True)
    payload = {"version": overlay.version, "values": overlay.values, "overrides": overlay.overrides}
    _atomic_write_text(target, json.dumps(payload, indent=2, ensure_ascii=False) + "\n", mode=0o600)
    return target


def _atomic_write_text(path: Path, payload: str, *, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    temp_path = Path(temp_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp_path, mode)
        os.replace(temp_path, path)
    except Exception:
        temp_path.unlink(missing_ok=True)
        raise


def _atomic_write_bytes(path: Path, payload: bytes, *, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    temp_path = Path(temp_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp_path, mode)
        os.replace(temp_path, path)
    except Exception:
        temp_path.unlink(missing_ok=True)
        raise


def validate_registry(
    expansions: list[Expansion],
    retired: list[RetiredTrigger],
    overlay: Overlay | None = None,
    *,
    require_local_values: bool = False,
    reserved: list[ReservedTrigger] | None = None,
    generated_help: GeneratedHelp | None = None,
) -> list[str]:
    errors: list[str] = []
    ids: dict[str, str] = {}
    triggers: dict[str, str] = {}
    phrases: dict[str, str] = {}

    for expansion in expansions:
        if expansion.ident in ids:
            errors.append(f"duplicate id: {expansion.ident}")
        ids[expansion.ident] = expansion.trigger
        if expansion.trigger in triggers:
            errors.append(f"duplicate trigger: {expansion.trigger}")
        triggers[expansion.trigger] = expansion.ident
        if not _trigger_form_ok(expansion.trigger):
            errors.append(f"unsupported trigger: {expansion.trigger}")
        if expansion.legacy_exception != (expansion.trigger in RETAINED_EXCEPTIONS):
            errors.append(f"{expansion.ident}: legacy_exception does not match retained exceptions")
        if expansion.help_group not in HELP_GROUP_ORDER:
            errors.append(f"{expansion.ident}: invalid help group")
        if expansion.phrase is None and not expansion.local_value_key:
            errors.append(f"{expansion.ident}: missing phrase and local_value_key")
        if (
            expansion.local_value_key
            and require_local_values
            and (overlay is None or expansion.local_value_key not in overlay.values)
        ):
            errors.append(f"{expansion.ident}: missing local overlay key {expansion.local_value_key}")
        if expansion.sensitivity == "public" and expansion.local_value_key:
            errors.append(f"{expansion.ident}: public sensitivity cannot use a local value key")
        if expansion.is_private and expansion.phrase:
            errors.append(f"{expansion.ident}: private expansion must not include a public phrase")
        if expansion.multiline and expansion.shell_safe:
            errors.append(f"{expansion.ident}: multiline expansions cannot be shell_safe")
        phrase = expansion.phrase
        if phrase is None and expansion.local_value_key and overlay is not None:
            phrase = overlay.values.get(expansion.local_value_key)
        if phrase is not None:
            errors.extend(_phrase_policy_errors(expansion, phrase))
        if "shortcut-library" in expansion.surfaces and expansion.is_private:
            errors.append(f"{expansion.ident}: private values cannot be published to shortcut-library")
        if expansion.phrase:
            prior = phrases.get(expansion.phrase)
            if prior and prior != expansion.ident and not expansion.duplicate_phrase_justification:
                errors.append(f"{expansion.ident}: duplicate phrase of {prior} without justification")
            phrases.setdefault(expansion.phrase, expansion.ident)
        for alias in expansion.replaces:
            if alias == expansion.trigger:
                errors.append(f"{expansion.ident}: replaces cannot include its canonical trigger")

    seen_retired: set[str] = set()
    for item in retired:
        if item.trigger in seen_retired:
            errors.append(f"duplicate retired trigger: {item.trigger}")
        seen_retired.add(item.trigger)
        if item.trigger in triggers:
            errors.append(f"retired trigger {item.trigger} still has a live canonical expansion")
        if item.replaced_by and item.replaced_by not in triggers:
            errors.append(f"retired trigger {item.trigger} replaced_by unknown trigger {item.replaced_by}")
        if item.trigger in {alias for expansion in expansions for alias in expansion.replaces}:
            errors.append(f"retired trigger {item.trigger} is also a predecessor")
    errors.extend(_ownership_errors(expansions, retired))
    folded: dict[str, str] = {}
    for trigger in triggers:
        _claim_folded(folded, trigger, errors)
    for expansion in expansions:
        if not expansion.enabled:
            continue
        for alias in expansion.replaces:
            _claim_folded(folded, alias, errors)
        if INVISIBLE_RE.search(expansion.trigger):
            errors.append(f"{expansion.ident}: trigger contains a suspicious invisible character")
        if (expansion.phrase is None) == (not expansion.local_value_key):
            if expansion.phrase is not None and expansion.local_value_key:
                errors.append(f"{expansion.ident}: phrase and local_value_key are both set")
    if reserved is not None:
        if not reserved:
            errors.append("reserved_triggers must not be empty")
        for item in reserved:
            if item.trigger in triggers:
                errors.append(f"reserved trigger {item.trigger} is defined as a replacement")
            _claim_folded(folded, item.trigger, errors)
    if generated_help is not None:
        if not _trigger_form_ok(generated_help.trigger, generated=True):
            errors.append("invalid generated help trigger")
        _claim_folded(folded, generated_help.trigger, errors)
        seen_members: set[str] = set()
        for page, members in generated_help.initial_membership:
            if not _trigger_form_ok(page, generated=True) or page == generated_help.trigger:
                errors.append(f"invalid reference trigger {page}")
            _claim_folded(folded, page, errors)
            for member in members:
                if member not in triggers:
                    errors.append(f"{page}: unknown member {member}")
                if member in seen_members:
                    errors.append(f"reference member repeated: {member}")
                seen_members.add(member)
    return errors


def _phrase_policy_errors(expansion: Expansion, phrase: str) -> list[str]:
    errors: list[str] = []
    if not phrase:
        errors.append(f"{expansion.ident}: empty phrase")
    if SECRET_RE.search(phrase):
        errors.append(f"{expansion.ident}: phrase looks like a secret")
    if PSEUDO_DYNAMIC_RE.search(phrase):
        errors.append(f"{expansion.ident}: pseudo-dynamic syntax is not allowed in Text Replacements")
    if INVISIBLE_RE.search(phrase):
        errors.append(f"{expansion.ident}: phrase contains a suspicious invisible character")
    if "\n" in phrase and not expansion.multiline:
        errors.append(f"{expansion.ident}: phrase contains newlines but multiline is false")
    if phrase.endswith("\n"):
        errors.append(f"{expansion.ident}: phrase must not end with a newline")
    if expansion.shell_safe and ("\n" in phrase or phrase.strip().startswith(("sudo ", "rm ", "curl "))):
        errors.append(f"{expansion.ident}: unsafe terminal classification")
    return errors


def validate_catalog(catalog: Catalog, overlay: Overlay | None = None, *, require_local_values: bool = False) -> list[str]:
    return validate_registry(
        catalog.expansions,
        catalog.retired,
        overlay,
        require_local_values=require_local_values,
        reserved=catalog.reserved,
        generated_help=catalog.generated_help,
    )


def _claim_folded(folded: dict[str, str], trigger: str, errors: list[str]) -> None:
    key = trigger.casefold()
    prior = folded.get(key)
    if prior is not None and prior != trigger:
        errors.append(f"case-folded trigger collision: {prior} and {trigger}")
        return
    if prior == trigger:
        errors.append(f"duplicate folded trigger: {trigger}")
        return
    folded[key] = trigger


def _ownership_errors(expansions: list[Expansion], retired: list[RetiredTrigger]) -> list[str]:
    errors: list[str] = []
    canonical = {item.trigger: item for item in expansions}
    owners: dict[str, str] = {}
    for expansion in expansions:
        for alias in expansion.replaces:
            if alias == expansion.trigger:
                continue
            if alias in canonical:
                errors.append(f"{expansion.ident}: predecessor {alias} is a canonical trigger")
            prior = owners.get(alias)
            if prior is not None and prior != expansion.trigger:
                errors.append(f"predecessor {alias} has multiple owners")
            owners[alias] = expansion.trigger
        for alias, _phrase in expansion.predecessor_phrases:
            if alias not in expansion.replaces:
                errors.append(f"{expansion.ident}: predecessor phrase {alias} is not a predecessor trigger")
    retired_triggers = {item.trigger for item in retired}
    for trigger in retired_triggers:
        if trigger in canonical:
            errors.append(f"retired trigger {trigger} is canonical")
    for expansion in expansions:
        seen = {alias for alias, _phrase in expansion.predecessor_phrases}
        if len(seen) != len(expansion.predecessor_phrases):
            errors.append(f"{expansion.ident}: repeated predecessor phrase")
    return errors


def prefix_warnings(triggers: list[str]) -> list[str]:
    """Diagnose prefix pairs without treating them as exact collisions."""
    warnings: list[str] = []
    ordered = sorted(set(triggers))
    for left, right in zip(ordered, ordered[1:], strict=False):
        if left != right and right.startswith(left):
            warnings.append(f"prefix pair {left} / {right} is not an exact duplicate")
    return warnings


def _trigger_form_ok(trigger: str, *, generated: bool = False) -> bool:
    if trigger in FORBIDDEN_TRIGGERS:
        return False
    if generated:
        return HELP_TRIGGER_RE.fullmatch(trigger) is not None or REFERENCE_TRIGGER_RE.fullmatch(trigger) is not None
    if trigger in RETAINED_EXCEPTIONS:
        return True
    return COMPACT_TRIGGER_RE.fullmatch(trigger) is not None


def resolve_phrase(expansion: Expansion, overlay: Overlay | None) -> str:
    if expansion.phrase is not None:
        return expansion.phrase
    if not expansion.local_value_key:
        raise AppleTextError(f"{expansion.ident}: no phrase or local key")
    if overlay is None or expansion.local_value_key not in overlay.values:
        raise AppleTextError(f"{expansion.ident}: missing local overlay key {expansion.local_value_key}")
    phrase = overlay.values[expansion.local_value_key]
    errors = _phrase_policy_errors(expansion, phrase)
    if errors:
        raise AppleTextError("; ".join(errors))
    return phrase


def parse_export(path: Path) -> tuple[list[dict[str, Any]], str]:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise AppleTextError(f"cannot read export {path}: {exc}") from exc
    entries, schema_id, _metadata = parse_export_bytes(raw)
    return entries, schema_id


def parse_export_bytes(raw: bytes) -> tuple[list[dict[str, Any]], str, dict[str, Any]]:
    try:
        data = plistlib.loads(raw)
    except Exception as exc:
        raise AppleTextError("invalid Apple Text Replacement plist") from exc
    return _normalize_plist(data)


def _normalize_plist(data: Any) -> tuple[list[dict[str, Any]], str, dict[str, Any]]:
    if isinstance(data, dict) and "NSUserDictionaryReplacementItems" in data:
        inner = data["NSUserDictionaryReplacementItems"]
        if not isinstance(inner, list):
            raise AppleTextError("NSUserDictionaryReplacementItems must be an array")
        metadata = {key: value for key, value in data.items() if key != "NSUserDictionaryReplacementItems"}
        if not _plist_safe(metadata):
            raise AppleTextError("unsupported wrapper metadata")
        return [_normalize_entry(item) for item in inner], "nsuserdictionary-replace-with", metadata
    if isinstance(data, list):
        schema = "shortcut-phrase"
        if any(isinstance(item, dict) and ("replace" in item or "with" in item) for item in data):
            schema = "replace-with"
        return [_normalize_entry(item) for item in data], schema, {}
    raise AppleTextError("unsupported Apple Text Replacement plist schema")


def _normalize_entry(item: Any) -> dict[str, Any]:
    if not isinstance(item, dict):
        raise AppleTextError("plist entry must be a dictionary")
    trigger = _paired_string(item, TRIGGER_KEY_CANDIDATES)
    phrase = _paired_string(item, PHRASE_KEY_CANDIDATES)
    if trigger is None or phrase is None:
        raise AppleTextError("plist entry missing trigger or phrase keys")
    extra = {
        key: value
        for key, value in item.items()
        if key not in {*TRIGGER_KEY_CANDIDATES, *PHRASE_KEY_CANDIDATES}
    }
    return {"shortcut": trigger, "phrase": phrase, **extra}


def _paired_string(item: dict[str, Any], keys: tuple[str, ...]) -> str | None:
    found: list[str] = []
    for key in keys:
        if key not in item:
            continue
        value = item[key]
        if not isinstance(value, str):
            raise AppleTextError(f"plist field {key} must be a string")
        found.append(value)
    if not found:
        return None
    if any(value != found[0] for value in found[1:]):
        raise AppleTextError("ambiguous plist key pair")
    return found[0]


def _first_string(item: dict[str, Any], keys: tuple[str, ...]) -> str | None:
    for key in keys:
        value = item.get(key)
        if isinstance(value, str):
            return value
    return None


def merge_export(
    existing: list[dict[str, Any]],
    expansions: list[Expansion],
    retired: list[RetiredTrigger],
    overlay: Overlay | None,
    *,
    schema_id: str = "shortcut-phrase",
    generated: list[Expansion] | None = None,
) -> MergePlan:
    plan = MergePlan(schema_id=schema_id)
    desired = [item for item in expansions if item.enabled and "text-replacement" in item.surfaces]
    desired.extend(generated or [])
    desired_by_trigger = {item.trigger: item for item in desired}
    alias_to_canonical: dict[str, Expansion] = {}
    for item in desired:
        for alias in item.replaces:
            alias_to_canonical[alias] = item
    retired_triggers = {item.trigger: item for item in retired}

    seen_triggers: dict[str, int] = {}
    for entry in existing:
        trigger = str(entry["shortcut"])
        seen_triggers[trigger] = seen_triggers.get(trigger, 0) + 1
    duplicates = sorted(trigger for trigger, count in seen_triggers.items() if count > 1)
    if duplicates:
        raise AppleTextError("duplicate triggers in export: " + ", ".join(duplicates))

    existing_by_trigger = {str(entry["shortcut"]): dict(entry) for entry in existing}
    used: set[str] = set()
    merged: list[dict[str, Any]] = []

    known_old = {
        (item.ident, alias): phrase
        for item in desired
        for alias, phrase in item.predecessor_phrases
    }

    def recognized(expansion: Expansion, alias: str, live_phrase: str) -> bool | None:
        key = (expansion.ident, alias)
        if key in known_old:
            return live_phrase == known_old[key]
        if expansion.local_value_key:
            if overlay is None or expansion.local_value_key not in overlay.values:
                return None
            return live_phrase == overlay.values[expansion.local_value_key]
        return live_phrase == expansion.phrase

    for trigger, entry in existing_by_trigger.items():
        live_phrase = entry.get("phrase")
        live_phrase = live_phrase if isinstance(live_phrase, str) else ""
        if trigger in desired_by_trigger:
            expansion = desired_by_trigger[trigger]
            try:
                phrase = resolve_phrase(expansion, overlay)
            except AppleTextError:
                if not expansion.local_value_key or (overlay and expansion.local_value_key in overlay.values):
                    raise
                plan.add("UNRESOLVED", trigger, f"local key {expansion.local_value_key} missing")
                plan.complete = False
                merged.append(entry)
                used.add(trigger)
                continue
            if live_phrase == phrase:
                plan.add("UNCHANGED", trigger)
                merged.append(entry)
            elif any(live_phrase == old for _alias, old in expansion.predecessor_phrases):
                plan.add("UPDATE", trigger, "recognized predecessor phrase")
                merged.append({**entry, "shortcut": expansion.trigger, "phrase": phrase})
            else:
                plan.add("CONFLICT", trigger, "canonical phrase differs from the desired phrase")
                plan.complete = False
                merged.append(entry)
            used.add(trigger)
            if expansion.is_private:
                plan.private_summaries.append(_private_status(expansion))
            continue
        if trigger in alias_to_canonical:
            expansion = alias_to_canonical[trigger]
            match = recognized(expansion, trigger, live_phrase)
            if match is True:
                plan.add("MIGRATE", trigger, f"{trigger} -> {expansion.trigger}")
            elif match is None:
                plan.add("UNRESOLVED", trigger, f"predecessor of {expansion.trigger}; local key missing")
                plan.complete = False
                merged.append(entry)
            else:
                plan.add("CONFLICT", trigger, f"predecessor of {expansion.trigger} differs from the recognized baseline")
                plan.complete = False
                merged.append(entry)
            used.add(trigger)
            continue
        if trigger in retired_triggers:
            plan.add("RETIRE", trigger, retired_triggers[trigger].reason)
            used.add(trigger)
            continue
        merged.append(entry)
        plan.preserved_unrelated += 1

    for expansion in sorted(desired, key=lambda item: item.trigger):
        if expansion.trigger in used or any(row.get("shortcut") == expansion.trigger for row in merged):
            continue
        try:
            phrase = resolve_phrase(expansion, overlay)
        except AppleTextError:
            if not expansion.local_value_key or (overlay and expansion.local_value_key in overlay.values):
                raise
            plan.add("UNRESOLVED", expansion.trigger, f"local key {expansion.local_value_key} missing")
            plan.complete = False
            if expansion.is_private:
                plan.private_summaries.append(_private_status(expansion))
            continue
        merged.append({"shortcut": expansion.trigger, "phrase": phrase})
        plan.add("ADD", expansion.trigger)
        if expansion.is_private:
            plan.private_summaries.append(_private_status(expansion))
        for alias in expansion.replaces:
            if alias in existing_by_trigger and alias not in used:
                plan.add("MIGRATE", alias, f"{alias} -> {expansion.trigger}")

    for trigger, item in retired_triggers.items():
        if trigger in existing_by_trigger and trigger not in used:
            plan.add("RETIRE", trigger, item.reason)
        elif trigger not in existing_by_trigger and not any(op.trigger == trigger for op in plan.operations):
            plan.add("RETIRE", trigger, f"{item.reason} (not present)")

    plan.merged = sorted(merged, key=lambda row: str(row.get("shortcut", "")))
    added = {item.trigger for item in plan.operations if item.kind == "ADD"}
    plan.additions = [row for row in plan.merged if str(row.get("shortcut", "")) in added]
    if plan.preserved_unrelated:
        plan.add("PRESERVE", "", f"{plan.preserved_unrelated} unrelated entries")
    return plan


def _private_status(expansion: Expansion) -> str:
    key = expansion.local_value_key or "generated reference"
    return f"{expansion.trigger} local key {key} status only"


def render_plist(
    entries: list[dict[str, Any]],
    *,
    schema_id: str = "shortcut-phrase",
    wrapper_metadata: dict[str, Any] | None = None,
) -> bytes:
    payload = []
    keys = ("replace", "with") if schema_id in {"replace-with", "nsuserdictionary-replace-with"} else ("shortcut", "phrase")
    for entry in entries:
        row: dict[str, Any] = {keys[0]: entry["shortcut"], keys[1]: entry["phrase"]}
        for key, value in entry.items():
            if key in {"shortcut", "phrase"}:
                continue
            if not _plist_safe(value):
                raise AppleTextError(f"unsupported plist field {key}")
            row[key] = value
        payload.append(row)
    payload.sort(key=lambda item: item[keys[0]])
    if schema_id == "nsuserdictionary-replace-with":
        metadata = wrapper_metadata or {}
        if "NSUserDictionaryReplacementItems" in metadata or not _plist_safe(metadata):
            raise AppleTextError("unsupported wrapper metadata")
        return plistlib.dumps({**metadata, "NSUserDictionaryReplacementItems": payload}, fmt=plistlib.FMT_XML, sort_keys=True)
    if schema_id not in {"shortcut-phrase", "replace-with"}:
        raise AppleTextError(f"unsupported plist schema: {schema_id}")
    return plistlib.dumps(payload, fmt=plistlib.FMT_XML, sort_keys=True)


def _plist_safe(value: Any) -> bool:
    if value is None or isinstance(value, (str, int, float, bool, bytes, datetime)):
        return True
    if isinstance(value, list):
        return all(_plist_safe(item) for item in value)
    if isinstance(value, dict):
        return all(isinstance(key, str) and _plist_safe(item) for key, item in value.items())
    return False


def lint_plist(path: Path) -> None:
    plutil = shutil.which("plutil")
    if plutil is None:
        try:
            plistlib.loads(path.read_bytes())
        except Exception as exc:
            raise AppleTextError(f"invalid plist {path}: {exc}") from exc
        return
    result = subprocess.run([plutil, "-lint", str(path)], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "plutil lint failed").strip()
        raise AppleTextError(detail)


def format_plan(plan: MergePlan) -> list[str]:
    lines: list[str] = []
    for operation in plan.operations:
        if operation.kind == "PRESERVE":
            lines.append(f"PRESERVE  {operation.detail}")
            continue
        suffix = f" {operation.detail}" if operation.detail else ""
        if operation.kind == "MIGRATE":
            lines.append(f"MIGRATE   {operation.detail}")
            continue
        lines.append(f"{operation.kind:<9} {operation.trigger}{suffix}".rstrip())
    for summary in plan.private_summaries:
        lines.append(f"PRIVATE   {summary}")
    return lines


def plan_to_json(plan: MergePlan) -> dict[str, Any]:
    return {
        "schemaId": plan.schema_id,
        "preservedUnrelated": plan.preserved_unrelated,
        "operations": [{"kind": item.kind, "trigger": item.trigger, "detail": item.detail} for item in plan.operations],
        "private": plan.private_summaries,
        "complete": plan.complete,
    }


def build_merge_plan(
    existing_export: Path,
    *,
    overlay_path: Path | None = None,
    root: Path | None = None,
    full_reference: bool = False,
    private_output: bool = False,
    source_bytes: bytes | None = None,
) -> MergePlan:
    catalog = load_catalog(root=root)
    overlay = load_overlay(overlay_path)
    errors = validate_catalog(catalog, overlay)
    if errors:
        raise AppleTextError("; ".join(errors))
    if source_bytes is None:
        _assert_regular_file(existing_export)
        source_bytes = existing_export.read_bytes()
    existing, schema_id, metadata = parse_export_bytes(source_bytes)
    generated: list[Expansion] = []
    pages: list[dict[str, Any]] = []
    manifest: dict[str, Any] | None = None
    if full_reference:
        pages, manifest = compile_reference_pages(catalog.expansions, catalog.generated_help, overlay)
        if manifest["missing"]:
            raise AppleTextError("reference coverage is incomplete")
        if any(page["private"] for page in pages) and not private_output:
            raise AppleTextError("full reference contains private pages; pass --private-output")
        missing = [
            item.local_value_key for item in catalog.expansions
            if item.enabled and item.local_value_key and (overlay is None or item.local_value_key not in overlay.values)
        ]
        if missing:
            raise AppleTextError("full reference requires local overlay keys: " + ", ".join(sorted(missing)))
        for page in pages:
            generated.append(_generated_expansion(page["trigger"], page["body"], private=page["private"]))
    help_body = render_help_index(catalog.expansions, catalog.reserved, catalog.generated_help, overlay, reference_profile=full_reference)
    generated.append(_generated_expansion(catalog.generated_help.trigger, help_body))
    plan = merge_export(existing, catalog.expansions, catalog.retired, overlay, schema_id=schema_id, generated=generated)
    plan.wrapper_metadata = metadata
    plan.reference_manifest = manifest
    plan.reference_pages = pages
    return plan


def _generated_expansion(trigger: str, phrase: str, *, private: bool = False) -> Expansion:
    return Expansion(
        ident=f"generated.{trigger[1:]}", trigger=trigger, category="markdown", enabled=True,
        multiline=True, sensitivity="private" if private else "public", shell_safe=False,
        surfaces=("text-replacement",), replaces=(), phrase=phrase,
        label=trigger, help_group="FORMATTING", kind="literal",
    )


def render_merged_plist(
    existing_export: Path,
    output: Path,
    *,
    overlay_path: Path | None = None,
    root: Path | None = None,
    full_reference: bool = False,
    private_output: bool = False,
) -> MergePlan:
    plan = build_merge_plan(
        existing_export, overlay_path=overlay_path, root=root,
        full_reference=full_reference, private_output=private_output,
    )
    if output.is_symlink() or output.exists() or output.resolve() == existing_export.resolve():
        raise AppleTextError("refusing to overwrite an existing or unsafe output")
    payload = render_plist(plan.merged, schema_id=plan.schema_id, wrapper_metadata=plan.wrapper_metadata)
    with tempfile.TemporaryDirectory() as temporary:
        candidate = Path(temporary) / "import.plist"
        candidate.write_bytes(payload)
        lint_plist(candidate)
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), PRIVATE_FILE_MODE)
    except OSError as exc:
        raise AppleTextError("cannot create a private output at the requested path") from exc
    try:
        with os.fdopen(descriptor, "wb") as handle:
            os.fchmod(handle.fileno(), PRIVATE_FILE_MODE)
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
    except Exception:
        output.unlink(missing_ok=True)
        raise
    return plan


def utc_stamp(now: datetime | None = None) -> str:
    current = now or datetime.now(UTC)
    return current.strftime("%Y%m%dT%H%M%SZ")


def _desired_counts(catalog: Catalog, plan: MergePlan) -> tuple[int, int]:
    base = len(catalog.expansions)
    enabled = sum(item.enabled and "text-replacement" in item.surfaces for item in catalog.expansions)
    pages = len(plan.reference_manifest["pages"]) if plan.reference_manifest else 0
    return base, enabled + 1 + pages


def stage_import(
    existing_export: Path,
    *,
    apply: bool,
    overlay_path: Path | None = None,
    state_dir: Path | None = None,
    root: Path | None = None,
    now: datetime | None = None,
    open_ui: bool = False,
    full_reference: bool = False,
    private_output: bool = False,
) -> dict[str, Any]:
    state = state_dir or default_state_path()
    result: dict[str, Any] = {"dry_run": not apply, "existingExport": str(existing_export)}
    if not apply:
        plan = build_merge_plan(
            existing_export, overlay_path=overlay_path, root=root,
            full_reference=full_reference, private_output=private_output,
        )
        result.update({"plan": format_plan(plan), "planJson": plan_to_json(plan), "complete": plan.complete})
        catalog = load_catalog(root=root)
        result["baseCount"], result["desiredCount"] = _desired_counts(catalog, plan)
        return result
    _assert_regular_file(existing_export)
    token = uuid.uuid4().hex
    _ensure_private_dir(state)
    lock_handle = _acquire_stage_lock(state)
    workspace: Path | None = None
    published: list[Path] = []
    try:
        _assert_regular_file(existing_export)
        source_bytes = existing_export.read_bytes()
        source_hash = hashlib.sha256(source_bytes).hexdigest()
        plan = build_merge_plan(
            existing_export, overlay_path=overlay_path, root=root,
            full_reference=full_reference, private_output=private_output, source_bytes=source_bytes,
        )
        catalog = load_catalog(root=root)
        result["plan"] = format_plan(plan)
        result["planJson"] = plan_to_json(plan)
        result["baseCount"], result["desiredCount"] = _desired_counts(catalog, plan)
        workspace = Path(tempfile.mkdtemp(prefix=".transaction-", dir=state))
        os.chmod(workspace, PRIVATE_DIR_MODE)
        backup_temp = workspace / "backup"
        staged_temp = workspace / "staged"
        backup_temp.mkdir(mode=PRIVATE_DIR_MODE)
        staged_temp.mkdir(mode=PRIVATE_DIR_MODE)
        backup_temp_file = backup_temp / existing_export.name
        _atomic_write_bytes(backup_temp_file, source_bytes, mode=PRIVATE_FILE_MODE)
        import_temp = staged_temp / "property list.plist"
        apple_temp = staged_temp / "Text Substitutions.plist"
        additions_temp = staged_temp / "additions.plist"
        payload = render_plist(plan.merged, schema_id=plan.schema_id, wrapper_metadata=plan.wrapper_metadata)
        _atomic_write_bytes(import_temp, payload, mode=PRIVATE_FILE_MODE)
        _atomic_write_bytes(apple_temp, payload, mode=PRIVATE_FILE_MODE)
        _atomic_write_bytes(additions_temp, render_plist(plan.additions, schema_id=plan.schema_id, wrapper_metadata=plan.wrapper_metadata), mode=PRIVATE_FILE_MODE)
        lint_plist(import_temp)
        lint_plist(apple_temp)
        lint_plist(additions_temp)
        plan_text = "\n".join(format_plan(plan)) + "\n"
        _atomic_write_text(
            staged_temp / "PLAN.md",
            f"# Text Replacement plan\n\n```\n{plan_text}```\n",
            mode=PRIVATE_FILE_MODE,
        )
        _atomic_write_text(staged_temp / "CLEANUP.md", _cleanup_markdown(plan), mode=PRIVATE_FILE_MODE)
        rollback = (
            "# Rollback\n\n"
            "Restaging the manifest backup does not remove entries imported after that backup.\n\n"
            "Drag the restaged plist through System Settings → Keyboard → Text Replacements.\n\n"
            "Do not edit TextReplacements.db.\n"
            "CLI: `just apple-text rollback`\n"
        )
        _atomic_write_text(staged_temp / "ROLLBACK.md", rollback, mode=PRIVATE_FILE_MODE)
        if plan.reference_manifest is not None:
            _atomic_write_text(staged_temp / "references.json", json.dumps(plan.reference_manifest, indent=2) + "\n", mode=PRIVATE_FILE_MODE)
            pages = [page["body"] for page in plan.reference_pages]
            _atomic_write_text(staged_temp / "REFERENCES.md", "\n".join(pages), mode=PRIVATE_FILE_MODE)
        manifest = {
            "id": token,
            "state": "staged",
            "complete": plan.complete,
            "sourceName": existing_export.name,
            "backupFile": existing_export.name,
            "backupSha256": source_hash,
            "deviceChecked": False,
        }
        _atomic_write_text(
            staged_temp / "manifest.json",
            json.dumps(manifest, indent=2) + "\n",
            mode=PRIVATE_FILE_MODE,
        )
        if hashlib.sha256(existing_export.read_bytes()).hexdigest() != source_hash:
            raise AppleTextError("source export changed during staging")
        backup_dir = state / "backups" / token
        staged_dir = state / "staged-imports" / token
        backup_export = backup_dir / existing_export.name
        import_plist = staged_dir / "property list.plist"
        apple_named = staged_dir / "Text Substitutions.plist"
        _ensure_private_dir(backup_dir.parent)
        _ensure_private_dir(staged_dir.parent)
        if backup_dir.exists() or staged_dir.exists():
            raise AppleTextError("staging transaction already exists")
        os.rename(backup_temp, backup_dir)
        published.append(backup_dir)
        os.rename(staged_temp, staged_dir)
        published.append(staged_dir)
        transaction = {
            "id": token,
            "timestamp": utc_stamp(now),
            "backup": str(backup_dir),
            "backupFile": str(backup_export),
            "backupSha256": source_hash,
            "staged": str(staged_dir),
            "manifest": str(staged_dir / "manifest.json"),
            "existingExport": str(backup_export),
            "importPlist": str(import_plist),
            "appleNamedPlist": str(apple_named),
            "state": "staged",
            "complete": plan.complete,
        }
        _atomic_write_text(state / "transaction.json", json.dumps(transaction, indent=2) + "\n", mode=PRIVATE_FILE_MODE)
    except Exception:
        for path in reversed(published):
            shutil.rmtree(path)
        raise
    finally:
        if workspace is not None:
            shutil.rmtree(workspace)
        _release_stage_lock(lock_handle)
    if open_ui:
        open_staging_surfaces(staged_dir)
    result.update(
        {
            "complete": plan.complete,
            "backup": str(backup_dir),
            "staged": str(staged_dir),
            "importPlist": str(import_plist),
            "appleNamedPlist": str(apple_named),
        }
    )
    return result


def _assert_regular_file(path: Path) -> None:
    if path.is_symlink() or not path.is_file():
        raise AppleTextError("source export must be a regular file")


def _ensure_private_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    os.chmod(path, PRIVATE_DIR_MODE)


def _exclusive_private_dir(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(path.parent, PRIVATE_DIR_MODE)
    path.mkdir(mode=PRIVATE_DIR_MODE, exist_ok=False)
    os.chmod(path, PRIVATE_DIR_MODE)


def _acquire_stage_lock(state: Path) -> Any:
    handle = (state / "stage.lock").open("a", encoding="utf-8")
    os.chmod(state / "stage.lock", PRIVATE_FILE_MODE)
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as exc:
        handle.close()
        raise AppleTextError("another staging transaction is running") from exc
    return handle


def _release_stage_lock(handle: Any) -> None:
    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    handle.close()


def _cleanup_markdown(plan: MergePlan) -> str:
    lines = ["# Cleanup", "", "Confirm before deleting leftover aliases from the live library:", ""]
    migrate = [item for item in plan.operations if item.kind == "MIGRATE"]
    retired_present = [
        item
        for item in plan.operations
        if item.kind == "RETIRE" and "(not present)" not in item.detail
    ]
    retired_absent = [
        item
        for item in plan.operations
        if item.kind == "RETIRE" and "(not present)" in item.detail
    ]
    if not migrate and not retired_present:
        lines.append("No leftover aliases from this plan need a live delete.")
    else:
        for item in migrate:
            lines.append(f"- `{item.trigger}` — migrated; {item.detail}")
        for item in retired_present:
            lines.append(f"- `{item.trigger}` — {item.detail}")
    if retired_absent:
        lines.extend(["", "Retired triggers not in the export (nothing to delete):"])
        for item in retired_absent:
            lines.append(f"- `{item.trigger}` — {item.detail}")
    return "\n".join(lines) + "\n"


def rollback_stage(
    backup_dir: Path | None = None,
    *,
    state_dir: Path | None = None,
    open_ui: bool = False,
) -> dict[str, Any]:
    state = state_dir or default_state_path()
    transaction_path = state / "transaction.json"
    if not transaction_path.is_file():
        raise AppleTextError("no transaction manifest exists")
    try:
        transaction = json.loads(transaction_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise AppleTextError("invalid transaction manifest") from exc
    declared = Path(str(transaction.get("backupFile", "")))
    if backup_dir is not None:
        declared_name = Path(str(transaction.get("backupFile", ""))).name
        declared = backup_dir / declared_name
    if not declared.is_file() or declared.is_symlink():
        raise AppleTextError("manifest backup is not a regular file")
    payload = declared.read_bytes()
    digest = hashlib.sha256(payload).hexdigest()
    if digest != transaction.get("backupSha256"):
        raise AppleTextError("backup bytes do not match the transaction manifest")
    token = uuid.uuid4().hex
    staged = state / "staged-imports" / f"rollback-{token}"
    _exclusive_private_dir(staged)
    restored = staged / declared.name
    _atomic_write_bytes(restored, payload, mode=PRIVATE_FILE_MODE)
    notes = (
        "# Rollback\n\n"
        "State: restaged. This is not manually applied and not device-verified.\n\n"
        "Dragging this plist does not remove entries imported after the backup.\n\n"
        f"File: `{restored.name}`\n"
    )
    _atomic_write_text(staged / "ROLLBACK.md", notes, mode=PRIVATE_FILE_MODE)
    if open_ui:
        open_staging_surfaces(staged)
    return {"staged": str(staged), "export": str(restored), "state": "restaged", "deviceChecked": False}


def _latest_backup(state: Path) -> Path:
    backups = state / "backups"
    if not backups.is_dir():
        raise AppleTextError("no backups exist")
    candidates = sorted((path for path in backups.iterdir() if path.is_dir()), reverse=True)
    if not candidates:
        raise AppleTextError("no backups exist")
    return candidates[0]


def open_staging_surfaces(staged_dir: Path) -> None:
    subprocess.run(["open", str(staged_dir)], check=False)
    for url in (
        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?TextReplacements",
        "x-apple.systempreferences:com.apple.preference.keyboard?Text",
    ):
        result = subprocess.run(["open", url], check=False, capture_output=True, text=True)
        if result.returncode == 0:
            return


def overlay_mode(path: Path | None = None) -> int | None:
    target = path or default_overlay_path()
    if not target.exists():
        return None
    return stat.S_IMODE(target.stat().st_mode)


def collect_text_doctor_checks(
    *,
    root: Path | None = None,
    overlay_path: Path | None = None,
    state_dir: Path | None = None,
    home: Path | None = None,
) -> list[dict[str, str]]:
    del home
    checks: list[dict[str, str]] = []
    expansions: list[Expansion] = []
    retired: list[RetiredTrigger] = []
    overlay: Overlay | None = None
    try:
        overlay = load_overlay(overlay_path)
        catalog = load_catalog(root=root)
        expansions, retired = catalog.expansions, catalog.retired
        errors = validate_catalog(catalog, overlay)
        if errors:
            checks.append(_check("text-registry", "fail", errors[0], "Fix the public registry or overlay."))
        else:
            checks.append(_check("text-registry", "ok", f"{len(expansions)} expansions validated"))
    except AppleTextError as exc:
        checks.append(_check("text-registry", "fail", str(exc), "Fix the public registry JSON."))
    overlay_file = overlay_path or default_overlay_path()
    if overlay is None:
        checks.append(_check("local-overlay", "warn", "overlay missing", f"Create {overlay_file} with mode 0600."))
    else:
        mode = overlay_mode(overlay_file)
        summary = "present"
        if "home_address" in overlay.values:
            summary = "present, home_address present"
        if "phone_number" in overlay.values:
            summary = summary + ", phone_number present"
        status = "ok" if mode == 0o600 else "warn"
        remediation = None if mode == 0o600 else "chmod 0600 the overlay file"
        checks.append(_check("local-overlay", status, summary, remediation))
    state = state_dir or default_state_path()
    backups = state / "backups"
    backup_count = len(list(backups.glob("*"))) if backups.is_dir() else 0
    checks.append(_check("backups", "ok" if backup_count else "warn", f"{backup_count} backup folders"))
    darwin = sys.platform == "darwin"
    checks.append(
        _check(
            "macos",
            "ok" if darwin else "warn",
            f"{sys.platform} {os.uname().machine if hasattr(os, 'uname') else ''}".strip(),
            None if darwin else "Live import is macOS-only.",
        )
    )
    checks.extend(live_text_library_checks(expansions, retired))
    return checks


def read_live_replacement_triggers(*, timeout: float = 60.0) -> list[str] | None:
    """Read live Text Replacement triggers. Never returns phrases."""
    if sys.platform != "darwin" or os.environ.get("DOTFILES_APPLE_TEXT_SKIP_LIVE") == "1":
        return None
    try:
        raw = subprocess.check_output(["defaults", "export", "NSGlobalDomain", "-"], timeout=timeout)
        data = plistlib.loads(raw)
    except (OSError, subprocess.SubprocessError, plistlib.InvalidFileException, ValueError, TypeError):
        return None
    items = data.get("NSUserDictionaryReplacementItems") if isinstance(data, dict) else None
    if not isinstance(items, list):
        return None
    triggers: list[str] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        trigger = _first_string(item, TRIGGER_KEY_CANDIDATES)
        if trigger:
            triggers.append(trigger)
    return triggers


def live_text_library_checks(
    expansions: list[Expansion],
    retired: list[RetiredTrigger],
) -> list[dict[str, str]]:
    checks: list[dict[str, str]] = []
    if sys.platform != "darwin":
        checks.append(_check("live-text-library", "warn", "skipped (not macOS)", "Live import is macOS-only."))
        checks.append(_check("live-leftovers", "warn", "skipped (not macOS)"))
        return checks
    if os.environ.get("DOTFILES_APPLE_TEXT_SKIP_LIVE") == "1":
        checks.append(_check("live-text-library", "skipped", "skipped"))
        checks.append(_check("live-leftovers", "skipped", "skipped"))
        return checks
    live = read_live_replacement_triggers()
    if live is None:
        checks.append(
            _check(
                "live-text-library",
                "warn",
                "could not read NSUserDictionaryReplacementItems",
                "Export Text Replacements from System Settings and pass --existing-export.",
            )
        )
        checks.append(
            _check(
                "live-leftovers",
                "warn",
                "could not inspect live library",
                "Export Text Replacements from System Settings.",
            )
        )
        return checks
    live_set = set(live)
    desired = [
        item.trigger
        for item in expansions
        if item.enabled and "text-replacement" in item.surfaces
    ]
    missing = [trigger for trigger in desired if trigger not in live_set]
    leftovers = sorted(
        {
            *[alias for item in expansions for alias in item.replaces if alias in live_set],
            *[item.trigger for item in retired if item.trigger in live_set],
        }
    )
    if missing:
        preview = ", ".join(missing[:8])
        extra = f" (+{len(missing) - 8} more)" if len(missing) > 8 else ""
        checks.append(
            _check(
                "live-text-library",
                "warn",
                f"{len(desired) - len(missing)}/{len(desired)} triggers present; missing {preview}{extra}",
                "Drag Text Substitutions.plist into System Settings → Keyboard → Text Replacements.",
            )
        )
    else:
        checks.append(_check("live-text-library", "ok", f"{len(desired)}/{len(desired)} triggers present"))
    if leftovers:
        checks.append(
            _check(
                "live-leftovers",
                "warn",
                ", ".join(leftovers),
                "After grouped confirmation, delete migrated/retired aliases from Text Replacements.",
            )
        )
    else:
        checks.append(_check("live-leftovers", "ok", "no migrated or retired aliases in the live library"))
    return checks


def latest_staged_dir(state_dir: Path | None = None) -> Path:
    state = state_dir or default_state_path()
    transaction = state / "transaction.json"
    if transaction.is_file():
        try:
            payload = json.loads(transaction.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise AppleTextError(f"invalid transaction.json: {exc}") from exc
        staged = Path(str(payload.get("staged", "")))
        if staged.is_dir():
            return staged
    raise AppleTextError("no staged import exists; run just apple-text stage --apply first")


def _check(name: str, status: str, summary: str, remediation: str | None = None) -> dict[str, str]:
    payload = {"name": name, "status": status, "summary": summary}
    if remediation:
        payload["remediation"] = remediation
    return payload


def public_expansions(expansions: list[Expansion], overlay: Overlay | None = None) -> list[tuple[Expansion, str]]:
    resolved: list[tuple[Expansion, str]] = []
    for expansion in expansions:
        if not expansion.enabled or expansion.is_private:
            continue
        if expansion.phrase is None:
            continue
        resolved.append((expansion, expansion.phrase))
    return resolved


def content_revision(expansions: list[Expansion], generated_help: GeneratedHelp) -> str:
    public = [
        (item.trigger, item.label, item.kind, item.help_group, item.enabled, item.phrase)
        for item in sorted(expansions, key=lambda item: item.trigger)
        if not item.is_private
    ]
    private_metadata = [
        (item.trigger, item.label, item.kind, item.help_group, item.enabled, item.local_value_key)
        for item in sorted(expansions, key=lambda item: item.trigger)
        if item.is_private
    ]
    data = (public, private_metadata, generated_help.trigger, generated_help.label, generated_help.page_budget)
    return hashlib.sha256(repr(data).encode("utf-8")).hexdigest()[:12]


def render_help_index(
    expansions: list[Expansion],
    reserved: list[ReservedTrigger],
    generated_help: GeneratedHelp,
    overlay: Overlay | None = None,
    *,
    reference_profile: bool = False,
) -> str:
    revision = content_revision(expansions, generated_help)
    lines = [
        f"Apple text replacements r:{revision}",
        "Rebuild and import to update installed help. Editing the registry alone does not update the phone.",
        'Text Replacement is not a modal command language. Plain ";" stays unassigned. A full literal trigger can still collide with ordinary prose. No universal backslash or doubled-prefix escape is established.',
    ]
    for item in reserved:
        lines.append(f"{item.trigger} is reserved ({item.provenance}) and is not a replacement.")
    enabled = [item for item in expansions if item.enabled]
    for group in HELP_GROUP_ORDER:
        members = sorted((item for item in enabled if item.help_group == group), key=lambda item: item.trigger)
        if not members:
            continue
        lines.append("")
        lines.append(group)
        for item in members:
            lines.append(f"{item.trigger}  {item.label}{_help_markers(item, overlay)}")
    lines.extend(
        [
            "",
            "HELP",
            f"{generated_help.trigger}  {generated_help.label}",
        ]
    )
    if reference_profile:
        pages, _manifest = compile_reference_pages(expansions, generated_help, overlay, enabled=True)
        for page in pages:
            marker = " [private]" if page["private"] else ""
            lines.append(f"{page['trigger']}  Full reference{marker}")
    lines.extend(
        [
            "",
            "Distinctions",
            ";check verifies requirements; ;tick inserts a character.",
            ";deps requests a dependency plan; ;todo inserts a checkbox.",
            ";read promises review and follow-up; ;rcvd only acknowledges receipt.",
            ";pnl is the panel; ;panel remains reserved for the browser.",
        ]
    )
    return "\n".join(lines) + "\n"


def _help_markers(expansion: Expansion, overlay: Overlay | None) -> str:
    markers = ""
    if expansion.kind == "editable-template":
        markers += " [edit]"
    if expansion.local_value_key:
        present = overlay is not None and expansion.local_value_key in overlay.values
        markers += " [local]" if present else " [local unresolved]"
    return markers


def compile_reference_pages(
    expansions: list[Expansion],
    generated_help: GeneratedHelp,
    overlay: Overlay | None = None,
    *,
    enabled: bool = True,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    by_trigger = {item.trigger: item for item in expansions if item.enabled or not enabled}
    budget = generated_help.page_budget
    initial = [(page, tuple(member for member in members if member in by_trigger)) for page, members in generated_help.initial_membership]
    assigned = {trigger for _page, members in initial for trigger in members}
    extras = tuple(item.trigger for item in sorted(expansions, key=lambda item: item.trigger) if item.enabled and item.trigger not in assigned)
    pages_in: list[tuple[str, tuple[str, ...]]] = [(page, members) for page, members in initial if members]
    if extras:
        pages_in.append((f";h{len(pages_in) + 1}", extras))
    rendered: list[dict[str, Any]] = []
    changes: list[dict[str, Any]] = []
    covered: list[str] = []
    number = 1
    for original_trigger, members in pages_in:
        pending = list(members)
        first = True
        while pending:
            chosen: list[str] = []
            while pending:
                trial = chosen + [pending[0]]
                body = _reference_body(f";h{number}", trial, by_trigger, overlay)
                if len(body) <= budget or not chosen:
                    chosen.append(pending.pop(0))
                    if len(body) > budget:
                        break
                    continue
                break
            trigger = f";h{number}"
            body = _reference_body(trigger, chosen, by_trigger, overlay)
            private = any(by_trigger[item].is_private for item in chosen if item in by_trigger)
            oversize = len(body) > budget
            rendered.append(
                {
                    "trigger": trigger,
                    "entries": chosen,
                    "body": body,
                    "private": private,
                    "characters": len(body),
                    "oversize": oversize,
                }
            )
            if first and (original_trigger != trigger or list(members) != chosen):
                changes.append({"trigger": original_trigger, "to": trigger, "entries": chosen})
            first = False
            covered.extend(chosen)
            number += 1
    base = [item.trigger for item in expansions if item.enabled]
    manifest = {
        "budget": budget,
        "pages": [{key: value for key, value in page.items() if key != "body"} for page in rendered],
        "pageChanges": changes,
        "covered": covered,
        "missing": [item for item in base if item not in covered],
        "deviceChecked": False,
    }
    return rendered, manifest


def _reference_body(
    trigger: str,
    members: list[str],
    by_trigger: dict[str, Expansion],
    overlay: Overlay | None,
) -> str:
    chunks = [trigger]
    for member in members:
        expansion = by_trigger[member]
        try:
            phrase = resolve_phrase(expansion, overlay)
        except AppleTextError:
            phrase = f"[unresolved local value: {expansion.local_value_key}]"
        chunks.append(member)
        chunks.append(phrase)
        chunks.append("---")
    if chunks[-1] == "---":
        chunks.pop()
    return "\n".join(chunks) + "\n"


def list_records(catalog: Catalog, overlay: Overlay | None = None) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for expansion in catalog.expansions:
        local_state = None
        if expansion.local_value_key:
            local_state = "present" if overlay and expansion.local_value_key in overlay.values else "missing"
        rows.append(
            {
                "id": expansion.ident,
                "trigger": expansion.trigger,
                "label": expansion.label,
                "category": expansion.category,
                "helpGroup": expansion.help_group,
                "kind": expansion.kind,
                "enabled": expansion.enabled,
                "sensitivity": expansion.sensitivity,
                "legacyException": expansion.legacy_exception,
                "localValueKey": expansion.local_value_key,
                "local": local_state,
            }
        )
    return rows


def show_phrase(catalog: Catalog, trigger: str, overlay: Overlay | None, *, private_output: bool) -> str:
    matches = [item for item in catalog.expansions if item.trigger == trigger]
    if not matches:
        if trigger == catalog.generated_help.trigger:
            return render_help_index(catalog.expansions, catalog.reserved, catalog.generated_help, overlay)
        raise AppleTextError(f"unknown trigger {trigger}")
    expansion = matches[0]
    if expansion.is_private and not private_output:
        raise AppleTextError(f"{trigger} is local-only; pass --private-output to show it")
    return resolve_phrase(expansion, overlay)


def verify_export(after: Path, expected: Path) -> dict[str, Any]:
    actual, _schema = parse_export(after)
    wanted, _expected_schema = parse_export(expected)
    actual_map = {str(item["shortcut"]): str(item["phrase"]) for item in actual}
    wanted_map = {str(item["shortcut"]): str(item["phrase"]) for item in wanted}
    missing = sorted(trigger for trigger in wanted_map if trigger not in actual_map)
    unexpected = sorted(trigger for trigger in actual_map if trigger not in wanted_map)
    divergent = sorted(
        trigger
        for trigger in wanted_map
        if trigger in actual_map and actual_map[trigger] != wanted_map[trigger]
    )
    return {
        "ok": not missing and not unexpected and not divergent,
        "missing": missing,
        "unexpected": unexpected,
        "divergent": divergent,
        "deviceChecked": False,
        "syncChecked": False,
    }
