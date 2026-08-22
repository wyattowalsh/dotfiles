"""Apple Text Replacement registry, overlay, merge, and staging helpers."""

from __future__ import annotations

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
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Final, Literal

REPO_ROOT: Final = Path(__file__).resolve().parent.parent
SCHEMA_VERSION: Final = 1
REGISTRY_RELATIVE: Final = Path("rig") / "home" / "private_dot_config" / "apple-text" / "expansions.json"
DEFAULT_OVERLAY: Final = Path.home() / ".config" / "apple-text" / "expansions.local.json"
DEFAULT_STATE: Final = Path.home() / ".local" / "state" / "dotfiles" / "apple-text"
NAMESPACE_PREFIXES: Final = ("my", "msg", "ai", "dev", "md", "sym")
NAMESPACE_EXCEPTIONS: Final = frozenset({"==+", "mdash", "ndash", "w4w"})
PSEUDO_DYNAMIC_RE: Final = re.compile(
    r"\{\{[^}]+\}\}|\$clipboard|%date%|\$\{[^}]+\}|%\w+%",
    re.IGNORECASE,
)
SECRET_RE: Final = re.compile(
    r"(?i)(sk-[a-z0-9]{16,}|api[_-]?key\s*[:=]|begin (rsa |openssh )?private key|ghp_[a-zA-Z0-9]{20,})",
)
TRIGGER_KEY_CANDIDATES: Final = ("shortcut", "replace")
PHRASE_KEY_CANDIDATES: Final = ("phrase", "with")
PlanOpKind = Literal["ADD", "UPDATE", "MIGRATE", "RETIRE", "PRESERVE", "PRIVATE"]


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

    @property
    def is_private(self) -> bool:
        return self.sensitivity == "private" or self.local_value_key is not None


@dataclass(frozen=True)
class RetiredTrigger:
    trigger: str
    reason: str
    replaced_by: str | None = None


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
    schema_id: str = "shortcut-phrase"
    preserved_unrelated: int = 0
    private_summaries: list[str] = field(default_factory=list)

    def add(self, kind: PlanOpKind, trigger: str, detail: str = "") -> None:
        self.operations.append(PlanOp(kind, trigger, detail))


def _repo_root(root: Path | None = None) -> Path:
    if root is not None:
        return root
    return REPO_ROOT


def fingerprint(value: str) -> str:
    """Return a short deterministic fingerprint that is safe to log."""
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:12]


def overlay_summary(value: str) -> dict[str, Any]:
    return {
        "present": True,
        "characters": len(value),
        "multiline": "\n" in value,
        "fingerprint": fingerprint(value),
    }


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
    ident = _require_str(raw, "id")
    trigger = _require_str(raw, "trigger")
    phrase = raw.get("phrase")
    local_key = raw.get("local_value_key")
    surfaces = raw.get("surfaces")
    replaces = raw.get("replaces")
    if not isinstance(surfaces, list) or not surfaces:
        raise AppleTextError(f"{ident}: surfaces must be a non-empty list")
    if not isinstance(replaces, list):
        raise AppleTextError(f"{ident}: replaces must be a list")
    return Expansion(
        ident=ident,
        trigger=trigger,
        category=_require_str(raw, "category"),
        enabled=bool(raw.get("enabled", True)),
        multiline=bool(raw.get("multiline", False)),
        sensitivity=_require_str(raw, "sensitivity"),
        shell_safe=bool(raw.get("shell_safe", False)),
        surfaces=tuple(str(item) for item in surfaces),
        replaces=tuple(str(item) for item in replaces),
        phrase=str(phrase) if isinstance(phrase, str) else None,
        local_value_key=str(local_key) if isinstance(local_key, str) and local_key else None,
        duplicate_phrase_justification=(
            str(raw["duplicate_phrase_justification"])
            if isinstance(raw.get("duplicate_phrase_justification"), str)
            else None
        ),
    )


def _require_str(raw: dict[str, Any], key: str) -> str:
    value = raw.get(key)
    if not isinstance(value, str) or not value:
        raise AppleTextError(f"expansion field {key!r} must be a non-empty string")
    return value


def load_registry(
    path: Path | None = None, *, root: Path | None = None
) -> tuple[list[Expansion], list[RetiredTrigger]]:
    target = path or registry_path(root)
    data = _read_json(target)
    if not isinstance(data, dict):
        raise AppleTextError(f"{target} must contain a JSON object")
    raw_expansions = data.get("expansions")
    raw_retired = data.get("retired_triggers")
    if not isinstance(raw_expansions, list) or not raw_expansions:
        raise AppleTextError("expansions must be a non-empty array")
    if not isinstance(raw_retired, list):
        raise AppleTextError("retired_triggers must be an array")
    expansions = [_expansion_from_mapping(item) for item in raw_expansions if isinstance(item, dict)]
    if len(expansions) != len(raw_expansions):
        raise AppleTextError("every expansion must be an object")
    retired = [
        RetiredTrigger(
            trigger=_require_str(item, "trigger"),
            reason=_require_str(item, "reason"),
            replaced_by=str(item["replaced_by"]) if isinstance(item.get("replaced_by"), str) else None,
        )
        for item in raw_retired
        if isinstance(item, dict)
    ]
    if len(retired) != len(raw_retired):
        raise AppleTextError("every retired trigger must be an object")
    return expansions, retired


def load_overlay(path: Path | None = None) -> Overlay | None:
    target = path or default_overlay_path()
    if not target.is_file():
        return None
    data = _read_json(target)
    if not isinstance(data, dict):
        raise AppleTextError(f"{target} must contain a JSON object")
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
    if version != SCHEMA_VERSION:
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
        if any(ch.isupper() for ch in expansion.trigger) and expansion.trigger not in NAMESPACE_EXCEPTIONS:
            errors.append(f"uppercase trigger rejected: {expansion.trigger}")
        if not _namespace_ok(expansion.trigger):
            errors.append(f"unsupported namespace: {expansion.trigger}")
        if expansion.phrase is None and not expansion.local_value_key:
            errors.append(f"{expansion.ident}: missing phrase and local_value_key")
        if expansion.phrase is not None and expansion.phrase == "":
            errors.append(f"{expansion.ident}: empty phrase")
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
        if expansion.phrase and SECRET_RE.search(expansion.phrase):
            errors.append(f"{expansion.ident}: phrase looks like a secret")
        if expansion.phrase and PSEUDO_DYNAMIC_RE.search(expansion.phrase):
            errors.append(f"{expansion.ident}: pseudo-dynamic syntax is not allowed in Text Replacements")
        if expansion.multiline and expansion.shell_safe:
            errors.append(f"{expansion.ident}: multiline expansions cannot be shell_safe")
        if expansion.phrase and "\n" in expansion.phrase and not expansion.multiline:
            errors.append(f"{expansion.ident}: phrase contains newlines but multiline is false")
        if expansion.phrase and expansion.phrase.endswith("\n"):
            errors.append(f"{expansion.ident}: phrase must not end with a newline")
        if (
            expansion.shell_safe
            and expansion.phrase
            and ("\n" in expansion.phrase or expansion.phrase.strip().startswith(("sudo ", "rm ", "curl ")))
        ):
            errors.append(f"{expansion.ident}: unsafe terminal classification")
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
    return errors


def _namespace_ok(trigger: str) -> bool:
    if trigger in NAMESPACE_EXCEPTIONS:
        return True
    return any(trigger.startswith(prefix) and trigger[len(prefix) :] != "" for prefix in NAMESPACE_PREFIXES)


def resolve_phrase(expansion: Expansion, overlay: Overlay | None) -> str:
    if expansion.phrase is not None:
        return expansion.phrase
    if not expansion.local_value_key:
        raise AppleTextError(f"{expansion.ident}: no phrase or local key")
    if overlay is None or expansion.local_value_key not in overlay.values:
        raise AppleTextError(f"{expansion.ident}: missing local overlay key {expansion.local_value_key}")
    return overlay.values[expansion.local_value_key]


def parse_export(path: Path) -> tuple[list[dict[str, Any]], str]:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise AppleTextError(f"cannot read export {path}: {exc}") from exc
    try:
        data = plistlib.loads(raw)
    except Exception as exc:
        raise AppleTextError(f"invalid plist {path}: {exc}") from exc
    entries, schema_id = _normalize_plist(data)
    return entries, schema_id


def _normalize_plist(data: Any) -> tuple[list[dict[str, Any]], str]:
    if isinstance(data, dict) and "NSUserDictionaryReplacementItems" in data:
        inner = data["NSUserDictionaryReplacementItems"]
        if not isinstance(inner, list):
            raise AppleTextError("NSUserDictionaryReplacementItems must be an array")
        return [_normalize_entry(item) for item in inner], "nsuserdictionary-replace-with"
    if isinstance(data, list):
        normalized = [_normalize_entry(item) for item in data]
        schema = "shortcut-phrase"
        if normalized and any(key in normalized[0] for key in ("replace", "with")):
            schema = "replace-with"
        return normalized, schema
    raise AppleTextError("unsupported Apple Text Replacement plist schema")


def _normalize_entry(item: Any) -> dict[str, Any]:
    if not isinstance(item, dict):
        raise AppleTextError("plist entry must be a dictionary")
    trigger = _first_string(item, TRIGGER_KEY_CANDIDATES)
    phrase = _first_string(item, PHRASE_KEY_CANDIDATES)
    if trigger is None or phrase is None:
        raise AppleTextError("plist entry missing trigger or phrase keys")
    extra = {key: value for key, value in item.items() if key not in {*TRIGGER_KEY_CANDIDATES, *PHRASE_KEY_CANDIDATES}}
    return {"shortcut": trigger, "phrase": phrase, **extra}


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
) -> MergePlan:
    plan = MergePlan(schema_id=schema_id)
    desired = [item for item in expansions if item.enabled and "text-replacement" in item.surfaces]
    desired_by_trigger = {item.trigger: item for item in desired}
    alias_to_canonical: dict[str, Expansion] = {}
    for item in desired:
        for alias in item.replaces:
            alias_to_canonical[alias] = item
    retired_triggers = {item.trigger: item for item in retired}

    existing_by_trigger = {str(entry["shortcut"]): dict(entry) for entry in existing}
    used: set[str] = set()
    merged: list[dict[str, Any]] = []

    for trigger, entry in existing_by_trigger.items():
        if trigger in desired_by_trigger:
            expansion = desired_by_trigger[trigger]
            phrase = resolve_phrase(expansion, overlay)
            updated = {**entry, "shortcut": expansion.trigger, "phrase": phrase}
            merged.append(updated)
            used.add(trigger)
            if entry.get("phrase") != phrase:
                plan.add("UPDATE", trigger)
            if expansion.is_private:
                plan.private_summaries.append(_private_line(expansion.trigger, phrase))
            continue
        if trigger in alias_to_canonical:
            expansion = alias_to_canonical[trigger]
            plan.add("MIGRATE", trigger, f"{trigger} -> {expansion.trigger}")
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
        phrase = resolve_phrase(expansion, overlay)
        merged.append({"shortcut": expansion.trigger, "phrase": phrase})
        plan.add("ADD", expansion.trigger)
        if expansion.is_private:
            plan.private_summaries.append(_private_line(expansion.trigger, phrase))
        for alias in expansion.replaces:
            if alias in existing_by_trigger and alias not in used:
                plan.add("MIGRATE", alias, f"{alias} -> {expansion.trigger}")

    for trigger, item in retired_triggers.items():
        if trigger in existing_by_trigger and trigger not in used:
            plan.add("RETIRE", trigger, item.reason)
        elif trigger not in existing_by_trigger and not any(op.trigger == trigger for op in plan.operations):
            plan.add("RETIRE", trigger, f"{item.reason} (not present)")

    plan.merged = sorted(merged, key=lambda row: str(row.get("shortcut", "")))
    if plan.preserved_unrelated:
        plan.add("PRESERVE", "", f"{plan.preserved_unrelated} unrelated entries")
    return plan


def _private_line(trigger: str, phrase: str) -> str:
    summary = overlay_summary(phrase)
    return f"{trigger} present, {summary['characters']} characters, fingerprint {summary['fingerprint']}"


def render_plist(entries: list[dict[str, Any]]) -> bytes:
    payload = [{"shortcut": str(entry["shortcut"]), "phrase": str(entry["phrase"])} for entry in entries]
    payload.sort(key=lambda item: item["shortcut"])
    return plistlib.dumps(payload, fmt=plistlib.FMT_XML, sort_keys=True)


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
    }


def build_merge_plan(
    existing_export: Path,
    *,
    overlay_path: Path | None = None,
    root: Path | None = None,
) -> MergePlan:
    expansions, retired = load_registry(root=root)
    overlay = load_overlay(overlay_path)
    errors = validate_registry(expansions, retired, overlay, require_local_values=True)
    if errors:
        raise AppleTextError("; ".join(errors))
    existing, schema_id = parse_export(existing_export)
    return merge_export(existing, expansions, retired, overlay, schema_id=schema_id)


def render_merged_plist(
    existing_export: Path,
    output: Path,
    *,
    overlay_path: Path | None = None,
    root: Path | None = None,
) -> MergePlan:
    plan = build_merge_plan(existing_export, overlay_path=overlay_path, root=root)
    output.parent.mkdir(parents=True, exist_ok=True)
    _atomic_write_bytes(output, render_plist(plan.merged))
    lint_plist(output)
    return plan


def utc_stamp(now: datetime | None = None) -> str:
    current = now or datetime.now(UTC)
    return current.strftime("%Y%m%dT%H%M%SZ")


def stage_import(
    existing_export: Path,
    *,
    apply: bool,
    overlay_path: Path | None = None,
    state_dir: Path | None = None,
    root: Path | None = None,
    now: datetime | None = None,
    open_ui: bool = False,
) -> dict[str, Any]:
    plan = build_merge_plan(existing_export, overlay_path=overlay_path, root=root)
    stamp = utc_stamp(now)
    state = state_dir or default_state_path()
    result: dict[str, Any] = {
        "dry_run": not apply,
        "plan": format_plan(plan),
        "planJson": plan_to_json(plan),
        "existingExport": str(existing_export),
    }
    if not apply:
        return result
    backup_dir = state / "backups" / stamp
    staged_dir = state / "staged-imports" / stamp
    backup_dir.mkdir(parents=True, exist_ok=True)
    staged_dir.mkdir(parents=True, exist_ok=True)
    backup_export = backup_dir / existing_export.name
    shutil.copy2(existing_export, backup_export)
    import_plist = staged_dir / "property list.plist"
    apple_named = staged_dir / "Text Substitutions.plist"
    payload = render_plist(plan.merged)
    _atomic_write_bytes(import_plist, payload)
    _atomic_write_bytes(apple_named, payload)
    lint_plist(import_plist)
    lint_plist(apple_named)
    plan_text = "\n".join(format_plan(plan)) + "\n"
    _atomic_write_text(staged_dir / "PLAN.md", f"# Text Replacement plan\n\n```\n{plan_text}```\n")
    cleanup = _cleanup_markdown(plan)
    rollback = (
        "# Rollback\n\n"
        f"Re-import `{backup_export}` through System Settings → Keyboard → Text Replacements.\n\n"
        "Do not edit TextReplacements.db.\n"
        f"CLI: `just apple-text rollback --backup {backup_dir}`\n"
    )
    _atomic_write_text(staged_dir / "CLEANUP.md", cleanup)
    _atomic_write_text(staged_dir / "ROLLBACK.md", rollback)
    transaction = {
        "timestamp": stamp,
        "backup": str(backup_dir),
        "staged": str(staged_dir),
        "existingExport": str(backup_export),
        "importPlist": str(import_plist),
        "appleNamedPlist": str(apple_named),
    }
    _atomic_write_text(state / "transaction.json", json.dumps(transaction, indent=2) + "\n")
    if open_ui:
        open_staging_surfaces(staged_dir)
    result.update(
        {
            "backup": str(backup_dir),
            "staged": str(staged_dir),
            "importPlist": str(import_plist),
            "appleNamedPlist": str(apple_named),
        }
    )
    return result


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
    source = backup_dir or _latest_backup(state)
    exports = sorted(path for path in source.iterdir() if path.is_file())
    if not exports:
        raise AppleTextError(f"backup {source} has no export file")
    stamp = utc_stamp()
    staged = state / "staged-imports" / f"rollback-{stamp}"
    staged.mkdir(parents=True, exist_ok=True)
    restored = staged / exports[0].name
    shutil.copy2(exports[0], restored)
    notes = f"# Rollback\n\nDrag `{restored.name}` into System Settings → Keyboard → Text Replacements.\n"
    _atomic_write_text(staged / "ROLLBACK.md", notes)
    if open_ui:
        open_staging_surfaces(staged)
    return {"staged": str(staged), "export": str(restored)}


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
    overlay = load_overlay(overlay_path)
    expansions: list[Expansion] = []
    retired: list[RetiredTrigger] = []
    try:
        expansions, retired = load_registry(root=root)
        errors = validate_registry(expansions, retired, overlay, require_local_values=False)
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
        has_address = "home_address" in overlay.values
        summary = "present"
        if has_address:
            info = overlay_summary(overlay.values["home_address"])
            summary = f"present, home_address {info['characters']} characters, fingerprint {info['fingerprint']}"
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
        checks.append(_check("live-text-library", "ok", "skipped"))
        checks.append(_check("live-leftovers", "ok", "skipped"))
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
