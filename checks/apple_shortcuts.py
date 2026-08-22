"""Apple Shortcuts recipe registry, public iCloud dictionary, and doctor checks."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Final

from apple_text import (
    AppleTextError,
    Expansion,
    Overlay,
    _atomic_write_text,
    _check,
    load_overlay,
    load_registry,
    public_expansions,
    validate_registry,
)

REPO_ROOT: Final = Path(__file__).resolve().parent.parent
REGISTRY_RELATIVE: Final = Path("rig") / "home" / "private_dot_config" / "apple-text" / "shortcuts.json"
ICLOUD_RELATIVE: Final = Path("Shortcuts") / "AppleText" / "registry.json"
TEXT_HUB_CHILDREN: Final = (
    "Build Prompt",
    "Transform Text",
    "Text Library",
    "Build Reply",
    "Copy Date",
    "Make Link",
    "Expand Anywhere",
)


@dataclass(frozen=True)
class Composition:
    ident: str
    label: str
    triggers: tuple[str, ...]


@dataclass(frozen=True)
class Recipe:
    ident: str
    name: str
    platforms: tuple[str, ...]
    inputs: tuple[str, ...]
    actions: tuple[str, ...]
    outputs: tuple[str, ...]
    permissions: tuple[str, ...]
    siri_phrase: str
    terminal_safety: str
    validation_steps: tuple[str, ...]
    describe_prompt: str
    mac_hotkey: str | None = None
    children: tuple[str, ...] = ()


def _repo_root(root: Path | None = None) -> Path:
    if root is not None:
        return root
    return REPO_ROOT


def shortcuts_registry_path(root: Path | None = None) -> Path:
    return _repo_root(root) / REGISTRY_RELATIVE


def load_shortcuts_registry(
    path: Path | None = None, *, root: Path | None = None
) -> tuple[list[Composition], list[Recipe]]:
    target = path or shortcuts_registry_path(root)
    data = json.loads(target.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise AppleTextError(f"{target} must contain a JSON object")
    compositions = [
        Composition(
            ident=str(item["id"]),
            label=str(item["label"]),
            triggers=tuple(str(trigger) for trigger in item["triggers"]),
        )
        for item in data.get("compositions", [])
        if isinstance(item, dict)
    ]
    recipes = [
        Recipe(
            ident=str(item["id"]),
            name=str(item["name"]),
            platforms=tuple(str(platform) for platform in item["platforms"]),
            inputs=tuple(str(value) for value in item.get("inputs", [])),
            actions=tuple(str(value) for value in item["actions"]),
            outputs=tuple(str(value) for value in item["outputs"]),
            permissions=tuple(str(value) for value in item.get("permissions", [])),
            siri_phrase=str(item["siri_phrase"]),
            terminal_safety=str(item["terminal_safety"]),
            validation_steps=tuple(str(value) for value in item["validation_steps"]),
            describe_prompt=str(item["describe_prompt"]),
            mac_hotkey=str(item["mac_hotkey"]) if item.get("mac_hotkey") else None,
            children=tuple(str(value) for value in item.get("children", [])),
        )
        for item in data.get("recipes", [])
        if isinstance(item, dict)
    ]
    return compositions, recipes


def validate_shortcuts(
    compositions: list[Composition],
    recipes: list[Recipe],
    expansions: list[Expansion],
) -> list[str]:
    errors: list[str] = []
    triggers = {item.trigger: item for item in expansions}
    recipe_names = {item.name: item for item in recipes}
    recipe_ids: set[str] = set()
    for recipe in recipes:
        if recipe.ident in recipe_ids:
            errors.append(f"duplicate recipe id: {recipe.ident}")
        recipe_ids.add(recipe.ident)
        prompt = recipe.describe_prompt.lower()
        if (
            "private" in prompt
            and "do not include private" not in prompt
            and any(token in prompt for token in ("home_address", "myaddr phrase"))
        ):
            errors.append(f"{recipe.ident}: describe prompt appears to contain private data")
        for child in recipe.children:
            if child not in recipe_names:
                errors.append(f"{recipe.ident}: unknown child {child}")
        if recipe.ident == "text-hub":
            for name in TEXT_HUB_CHILDREN:
                if name not in recipe.children:
                    errors.append(f"text-hub must reference child {name}")
        if not recipe.platforms:
            errors.append(f"{recipe.ident}: platforms required")
        if recipe.ident == "expand-anywhere" and tuple(recipe.platforms) != ("macOS",):
            errors.append("expand-anywhere must be macOS-only")
        if ".shortcut" in prompt and not any(token in prompt for token in ("do not", "don't", "never")):
            errors.append(f"{recipe.ident}: recipes must not claim to emit .shortcut files")
    for composition in compositions:
        for trigger in composition.triggers:
            if trigger not in triggers:
                errors.append(f"{composition.ident}: unknown trigger {trigger}")
            elif triggers[trigger].is_private:
                errors.append(f"{composition.ident}: cannot compose private trigger {trigger}")
    if "Text Hub" not in recipe_names:
        errors.append("missing Text Hub recipe")
    return errors


def render_public_shortcut_registry(
    expansions: list[Expansion],
    compositions: list[Composition],
    overlay: Overlay | None = None,
) -> dict[str, Any]:
    entries: dict[str, Any] = {}
    by_trigger = {item.trigger: phrase for item, phrase in public_expansions(expansions, overlay)}
    for expansion, phrase in public_expansions(expansions, overlay):
        entries[expansion.trigger] = {
            "id": expansion.ident,
            "label": expansion.trigger,
            "category": expansion.category,
            "text": phrase,
            "composed": False,
        }
    for composition in compositions:
        parts: list[str] = []
        for trigger in composition.triggers:
            if trigger not in by_trigger:
                raise AppleTextError(f"{composition.ident}: missing public trigger {trigger}")
            parts.append(by_trigger[trigger])
        entries[composition.ident] = {
            "id": composition.ident,
            "label": composition.label,
            "category": "compose",
            "text": "\n\n".join(parts),
            "composed": True,
            "triggers": list(composition.triggers),
        }
    ordered = dict(sorted(entries.items(), key=lambda item: item[0]))
    return {"version": 1, "entries": ordered}


def detect_icloud_drive(home: Path | None = None) -> Path | None:
    override = os.environ.get("DOTFILES_APPLE_ICLOUD")
    if override:
        candidate = Path(override)
        return candidate if candidate.is_dir() else None
    root = (home or Path.home()) / "Library" / "Mobile Documents" / "com~apple~CloudDocs"
    if root.is_dir():
        return root
    return None


def default_icloud_registry_path(home: Path | None = None) -> Path | None:
    cloud = detect_icloud_drive(home)
    if cloud is None:
        return None
    return cloud / ICLOUD_RELATIVE


def sync_public_registry(
    *,
    apply: bool,
    destination: Path | None = None,
    root: Path | None = None,
    overlay_path: Path | None = None,
    home: Path | None = None,
) -> dict[str, Any]:
    expansions, retired = load_registry(root=root)
    overlay = load_overlay(overlay_path)
    compositions, recipes = load_shortcuts_registry(root=root)
    errors = [
        *validate_registry(expansions, retired, overlay),
        *validate_shortcuts(compositions, recipes, expansions),
    ]
    if errors:
        raise AppleTextError("; ".join(errors))
    payload = render_public_shortcut_registry(expansions, compositions, overlay)
    target = destination or default_icloud_registry_path(home)
    result: dict[str, Any] = {
        "dry_run": not apply,
        "destination": str(target) if target else None,
        "entryCount": len(payload["entries"]),
        "icloudAvailable": target is not None,
    }
    if target is None:
        raise AppleTextError("iCloud Drive is unavailable")
    if not apply:
        return result
    if destination is None and sys.platform != "darwin":
        raise AppleTextError("iCloud registry sync is only supported on macOS")
    _atomic_write_text(target, json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
    result["wrote"] = True
    return result


def recipe_plan(root: Path | None = None) -> dict[str, Any]:
    compositions, recipes = load_shortcuts_registry(root=root)
    expansions, _retired = load_registry(root=root)
    errors = validate_shortcuts(compositions, recipes, expansions)
    if errors:
        raise AppleTextError("; ".join(errors))
    return {
        "recipes": [
            {
                "id": recipe.ident,
                "name": recipe.name,
                "platforms": list(recipe.platforms),
                "siriPhrase": recipe.siri_phrase,
                "macHotkey": recipe.mac_hotkey,
                "permissions": list(recipe.permissions),
                "describePrompt": recipe.describe_prompt,
            }
            for recipe in recipes
        ],
        "compositions": [
            {"id": item.ident, "label": item.label, "triggers": list(item.triggers)} for item in compositions
        ],
    }


def export_describe_prompts(destination: Path, *, root: Path | None = None) -> Path:
    plan = recipe_plan(root=root)
    destination.mkdir(parents=True, exist_ok=True)
    for recipe in plan["recipes"]:
        path = destination / f"{recipe['id']}.txt"
        _atomic_write_text(path, recipe["describePrompt"].rstrip() + "\n")
    index = destination / "INDEX.md"
    lines = ["# Describe a Shortcut prompts", ""]
    for recipe in plan["recipes"]:
        lines.append(f"- `{recipe['name']}` — `{recipe['id']}.txt`")
    _atomic_write_text(index, "\n".join(lines) + "\n")
    return destination


def list_installed_shortcut_names(*, timeout: float = 30.0) -> list[str] | None:
    binary = shutil.which("shortcuts")
    if binary is None or os.environ.get("DOTFILES_APPLE_TEXT_SKIP_LIVE") == "1":
        return None
    try:
        run = subprocess.run(
            [binary, "list"],
            capture_output=True,
            text=True,
            check=False,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if run.returncode != 0:
        return None
    return [line.strip() for line in run.stdout.splitlines() if line.strip()]


def live_shortcut_checks(recipes: list[Recipe]) -> list[dict[str, str]]:
    if sys.platform != "darwin":
        return [_check("live-shortcuts", "warn", "skipped (not macOS)", "Shortcuts install is macOS-only.")]
    if os.environ.get("DOTFILES_APPLE_TEXT_SKIP_LIVE") == "1":
        return [_check("live-shortcuts", "ok", "skipped")]
    names = list_installed_shortcut_names()
    if names is None:
        return [
            _check(
                "live-shortcuts",
                "warn",
                "could not list Shortcuts",
                "Install macOS Shortcuts and rerun just apple-text doctor.",
            )
        ]
    installed = set(names)
    missing = [recipe.name for recipe in recipes if recipe.name not in installed]
    if missing:
        return [
            _check(
                "live-shortcuts",
                "warn",
                f"{len(recipes) - len(missing)}/{len(recipes)} recipes installed; missing {', '.join(missing)}",
                "Build them in Apple Shortcuts from just apple-text shortcuts-export --apply. Do not compile unofficial .shortcut files.",
            )
        ]
    return [_check("live-shortcuts", "ok", f"{len(recipes)}/{len(recipes)} recipes installed")]


def collect_shortcuts_doctor_checks(
    *,
    root: Path | None = None,
    home: Path | None = None,
) -> list[dict[str, str]]:
    checks: list[dict[str, str]] = []
    darwin = sys.platform == "darwin"
    binary = shutil.which("shortcuts")
    if binary:
        help_run = subprocess.run([binary, "help"], capture_output=True, text=True, check=False)
        checks.append(
            _check(
                "shortcuts-cli",
                "ok" if help_run.returncode == 0 else "warn",
                binary,
                None if help_run.returncode == 0 else "Install Apple Shortcuts.",
            )
        )
    else:
        checks.append(
            _check(
                "shortcuts-cli",
                "warn" if not darwin else "fail",
                "shortcuts CLI not found",
                "Install macOS Shortcuts.",
            )
        )
    cloud = detect_icloud_drive(home)
    checks.append(
        _check(
            "icloud-drive",
            "ok" if cloud else "warn",
            str(cloud) if cloud else "iCloud Drive not found",
            None if cloud else "Sign in to iCloud Drive.",
        )
    )
    registry = default_icloud_registry_path(home)
    if registry is not None and registry.is_file():
        try:
            payload = json.loads(registry.read_text(encoding="utf-8"))
            entries = payload.get("entries") if isinstance(payload, dict) else None
            count = len(entries) if isinstance(entries, dict) else 0
            has_private = isinstance(entries, dict) and "myaddr" in entries
            checks.append(
                _check(
                    "icloud-registry",
                    "fail" if has_private else "ok",
                    f"{count} public entries" if not has_private else "public registry contains myaddr",
                    None if not has_private else "Re-run just apple-text shortcuts-sync --apply after fixing private filters.",
                )
            )
        except (OSError, json.JSONDecodeError) as exc:
            checks.append(_check("icloud-registry", "fail", str(exc), "Fix or regenerate the iCloud registry JSON."))
    else:
        checks.append(
            _check(
                "icloud-registry",
                "warn",
                "registry.json missing",
                "Run just apple-text shortcuts-sync --apply.",
            )
        )
    try:
        expansions, retired = load_registry(root=root)
        compositions, recipes = load_shortcuts_registry(root=root)
        errors = validate_shortcuts(compositions, recipes, expansions)
        if errors:
            checks.append(
                _check(
                    "shortcuts-registry",
                    "fail",
                    errors[0],
                    "Fix rig/home/private_dot_config/apple-text/shortcuts.json.",
                )
            )
        else:
            checks.append(_check("shortcuts-registry", "ok", f"{len(recipes)} recipes"))
        checks.extend(live_shortcut_checks(recipes))
        _ = retired
    except (OSError, json.JSONDecodeError, AppleTextError) as exc:
        checks.append(_check("shortcuts-registry", "fail", str(exc), "Fix the Shortcuts recipe registry."))
    return checks
