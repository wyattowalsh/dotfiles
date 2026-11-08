"""Offline policy checks for the compact Apple text registry."""

from __future__ import annotations

import copy
import dataclasses
import hashlib
import json
import os
import plistlib
import stat
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "checks"))

import apple_text
import apple_text_cli


def main() -> None:
    catalog = apple_text.load_catalog()
    triggers = {item.trigger: item for item in catalog.expansions}
    if len(catalog.expansions) != 51:
        raise SystemExit(f"expected 51 expansions, got {len(catalog.expansions)}")
    exceptions = {item.trigger for item in catalog.expansions if item.legacy_exception}
    if exceptions != {"==+", "myEn", "w4w"}:
        raise SystemExit(f"retained exceptions changed: {exceptions}")
    if [item.trigger for item in catalog.reserved] != [";panel"]:
        raise SystemExit("reserved trigger set changed")
    if triggers["w4w"].phrase != "https://w4w.dev" or triggers["w4w"].ident != "identity.site":
        raise SystemExit("identity.site must stay on w4w")
    if triggers[";site"].phrase != "https://www.w4w.dev":
        raise SystemExit(";site must stay distinct from w4w")
    if triggers[";todo"].phrase != "- [ ] " or triggers[";done"].phrase != "- [x] ":
        raise SystemExit("task phrases lost their trailing spaces")
    if triggers[";em"].phrase != "—" or triggers[";en"].phrase != "–":
        raise SystemExit("dash characters changed")
    signature = triggers[";sig"].phrase or ""
    if "\n" not in signature or signature.endswith("\n"):
        raise SystemExit("signature newlines changed")
    if any("myEn" in item.replaces for item in catalog.expansions):
        raise SystemExit("myEn must not be a predecessor")
    phrase_baseline = {trigger: item.phrase for trigger, item in triggers.items()}
    payload = json.dumps(phrase_baseline, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    digest = hashlib.sha256(payload.encode("utf-8")).hexdigest()
    if digest != "b1e9e1a757b9d249824ea52eb5b485c9a8a5bc588ce17eb7fd810770376ae874":
        raise SystemExit("public phrase baseline differs from supplied seed")
    overlay = apple_text.load_overlay()
    _pages, manifest = apple_text.compile_reference_pages(
        catalog.expansions, catalog.generated_help, overlay
    )
    base = [item.trigger for item in catalog.expansions if item.enabled]
    covered = manifest["covered"]
    if sorted(covered) != sorted(base) or len(covered) != len(set(covered)) or manifest["missing"]:
        raise SystemExit(
            f"reference coverage mismatch missing={set(base) - set(covered)} extra={set(covered) - set(base)}"
        )
    if ";help" in covered or any(item.startswith(";h") for item in covered):
        raise SystemExit("generated help was inlined into a reference page")
    blob = (ROOT / "rig/home/private_dot_config/apple-text/expansions.json").read_text(encoding="utf-8")
    for banned in ("100 Example", "555-0199"):
        if banned in blob:
            raise SystemExit(f"canonical registry contains {banned}")

    tiny = dataclasses.replace(catalog.generated_help, page_budget=1)
    pages, _manifest = apple_text.compile_reference_pages(catalog.expansions, tiny, None)
    by_trigger = {item.trigger: item for item in catalog.expansions}
    oversized = [page for page in pages if page["oversize"]]
    if not oversized:
        raise SystemExit("expected an oversize reference page")
    for page in oversized:
        whole = apple_text._reference_body(page["trigger"], page["entries"], by_trigger, None)
        if page["body"] != whole:
            raise SystemExit("oversize reference page was truncated")

    with tempfile.TemporaryDirectory() as directory:
        scratch = Path(directory)
        source = scratch / "source.plist"
        source.write_bytes(plistlib.dumps([]))
        complete = apple_text.build_merge_plan(source, overlay_path=Path(os.environ["DOTFILES_APPLE_TEXT_OVERLAY"]))
        if len(complete.merged) != 52 or ";help" not in {row["shortcut"] for row in complete.merged}:
            raise SystemExit("compact default profile must contain 51 base records plus generated help")
        if len(complete.additions) != 52:
            raise SystemExit("empty export must add the 52-entry default profile")
        reference = apple_text.build_merge_plan(source, overlay_path=Path(os.environ["DOTFILES_APPLE_TEXT_OVERLAY"]), full_reference=True, private_output=True)
        if len(reference.merged) != 52 + len(reference.reference_manifest["pages"]):
            raise SystemExit("optional reference pages are missing from the import")
        wrapped = scratch / "wrapped.plist"
        wrapped.write_bytes(plistlib.dumps({"NSUserDictionaryReplacementItems": [], "Marker": "retained"}))
        output = scratch / "render.plist"
        apple_text.render_merged_plist(wrapped, output, overlay_path=Path(os.environ["DOTFILES_APPLE_TEXT_OVERLAY"]))
        result = plistlib.loads(output.read_bytes())
        if result.get("Marker") != "retained" or len(result["NSUserDictionaryReplacementItems"]) != 52:
            raise SystemExit("wrapper metadata or generated help was lost")
        if stat.S_IMODE(output.stat().st_mode) != 0o600:
            raise SystemExit("rendered plist is not private")
        try:
            apple_text.render_merged_plist(wrapped, output, overlay_path=Path(os.environ["DOTFILES_APPLE_TEXT_OVERLAY"]))
        except apple_text.AppleTextError:
            pass
        else:
            raise SystemExit("render overwrote an existing output")
        state = scratch / "state"
        with patch.object(apple_text, "lint_plist", side_effect=apple_text.AppleTextError("synthetic lint failure")):
            try:
                apple_text.stage_import(source, apply=True, overlay_path=Path(os.environ["DOTFILES_APPLE_TEXT_OVERLAY"]), state_dir=state)
            except apple_text.AppleTextError:
                pass
            else:
                raise SystemExit("injected lint failure was accepted")
        if (state / "backups").exists() and list((state / "backups").iterdir()):
            raise SystemExit("failed staging published a backup")
        if (state / "transaction.json").exists():
            raise SystemExit("failed staging published a transaction")

    raw = json.loads(blob)
    broken = copy.deepcopy(raw)
    broken["expansions"][0]["enabled"] = "true"
    broken_path = Path(os.environ["TMP_APPLE"]) / "string-bool.json"
    broken_path.write_text(json.dumps(broken), encoding="utf-8")
    try:
        apple_text.load_catalog(broken_path)
    except apple_text.AppleTextError as exc:
        if "boolean" not in str(exc):
            raise
    else:
        raise SystemExit("string boolean was accepted")

    invalid_fields = (
        ("root", lambda payload: payload.__setitem__("unexpected", True)),
        ("version-bool", lambda payload: payload.__setitem__("version", True)),
        ("help-trigger", lambda payload: payload["generated_help"].__setitem__("trigger", ";other")),
        ("reserved", lambda payload: payload["reserved_triggers"][0].__setitem__("unexpected", True)),
        ("help", lambda payload: payload["generated_help"].__setitem__("unexpected", True)),
        ("predecessor", lambda payload: payload["expansions"][0]["predecessor_phrases"].append({"trigger": "old", "phrase": "text", "unexpected": True})),
        ("retired", lambda payload: payload["retired_triggers"].append({"trigger": "old", "reason": "gone", "replaced_by": 3})),
    )
    for name, corrupt in invalid_fields:
        candidate = copy.deepcopy(raw)
        corrupt(candidate)
        path = Path(os.environ["TMP_APPLE"]) / f"invalid-{name}.json"
        path.write_text(json.dumps(candidate), encoding="utf-8")
        try:
            apple_text.load_catalog(path)
        except apple_text.AppleTextError:
            pass
        else:
            raise SystemExit(f"invalid {name} fields were accepted")
    for phrase in ("", "abc​def", "{{today}}", "sk-1234567890abcdef", "line\n"):
        synthetic = apple_text.Overlay(2, {"home_address": phrase}, {})
        issues = apple_text.validate_registry(catalog.expansions, catalog.retired, synthetic, reserved=catalog.reserved, generated_help=catalog.generated_help)
        if not any("identity.address" in issue for issue in issues):
            raise SystemExit("unsafe local phrase was accepted")
        if any(phrase and phrase in issue for issue in issues):
            raise SystemExit("unsafe private value leaked in validation")
    records = apple_text.list_records(catalog, overlay)
    if any("phrase" in record for record in records):
        raise SystemExit("list records contains phrase bodies")

    panel = copy.deepcopy(raw)
    clone = copy.deepcopy(panel["expansions"][0])
    clone["id"] = "symbol.panel-forbidden"
    clone["trigger"] = ";panel"
    clone["phrase"] = "should not exist"
    clone["legacy_exception"] = False
    clone["replaces"] = []
    panel["expansions"].append(clone)
    panel_path = Path(os.environ["TMP_APPLE"]) / "panel.json"
    panel_path.write_text(json.dumps(panel), encoding="utf-8")
    loaded = apple_text.load_catalog(panel_path)
    errors = apple_text.validate_registry(
        loaded.expansions,
        loaded.retired,
        reserved=loaded.reserved,
        generated_help=loaded.generated_help,
    )
    if not any(";panel" in item and "reserved" in item for item in errors):
        raise SystemExit(errors)

    state = Path(os.environ["DOTFILES_APPLE_TEXT_STATE"])
    for path in state.rglob("*"):
        mode = stat.S_IMODE(path.stat().st_mode)
        expected = 0o700 if path.is_dir() else 0o600
        if mode != expected:
            raise SystemExit(f"mode {oct(mode)} on {path}, expected {oct(expected)}")

    saved_platform = sys.platform
    sys.platform = "linux"
    try:
        apple_text_cli._copy_text("synthetic")
    except SystemExit as exc:
        if exc.code != 2:
            raise SystemExit(f"clipboard exit {exc.code}")
    else:
        raise SystemExit("non-macOS clipboard did not exit")
    finally:
        sys.platform = saved_platform
    print("registry-policy-ok")


if __name__ == "__main__":
    main()
