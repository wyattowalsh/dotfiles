"""CLI for Apple-native Text Replacement merge and Shortcut recipes."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

CHECKS_DIR = Path(__file__).resolve().parent
if str(CHECKS_DIR) not in sys.path:
    sys.path.insert(0, str(CHECKS_DIR))

from apple_shortcuts import (  # noqa: E402
    collect_shortcuts_doctor_checks,
    export_describe_prompts,
    load_shortcuts_registry,
    recipe_plan,
    sync_public_registry,
    validate_shortcuts,
)
from apple_text import (  # noqa: E402
    AppleTextError,
    build_merge_plan,
    collect_text_doctor_checks,
    default_state_path,
    format_plan,
    latest_staged_dir,
    load_catalog,
    load_overlay,
    open_staging_surfaces,
    plan_to_json,
    render_help_index,
    render_merged_plist,
    rollback_stage,
    show_phrase,
    stage_import,
    verify_export,
    compile_reference_pages,
    list_records,
    validate_catalog,
)


def _emit(format_: str, *, text_lines: list[str], payload: dict[str, Any]) -> None:
    if format_ == "json":
        sys.stdout.write(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
        return
    sys.stdout.write("\n".join(text_lines) + "\n")


def _fail(message: str, *, code: int = 1) -> None:
    sys.stderr.write(f"{message}\n")
    raise SystemExit(code)


def cmd_validate(args: argparse.Namespace) -> int:
    overlay = Path(args.local_overlay) if args.local_overlay else None
    try:
        catalog = load_catalog()
        overlay_data = load_overlay(overlay)
        compositions, recipes = load_shortcuts_registry()
        errors = [
            *validate_catalog(catalog, overlay_data),
            *validate_shortcuts(compositions, recipes, catalog.expansions),
        ]
    except AppleTextError as exc:
        errors = [str(exc)]
    payload = {"ok": not errors, "errors": errors}
    _emit(
        args.format,
        text_lines=["valid" if not errors else "invalid", *errors],
        payload=payload,
    )
    return 0 if not errors else 1


def cmd_doctor(args: argparse.Namespace) -> int:
    checks = [*collect_text_doctor_checks(), *collect_shortcuts_doctor_checks()]
    counts = {
        "ok": sum(1 for check in checks if check["status"] == "ok"),
        "warn": sum(1 for check in checks if check["status"] == "warn"),
        "fail": sum(1 for check in checks if check["status"] == "fail"),
    }
    payload = {"ok": counts["fail"] == 0, "summary": {"total": len(checks), **counts}, "checks": checks}
    lines = [
        f"Doctor summary: {len(checks)} checks, {counts['ok']} ok, {counts['warn']} warn, {counts['fail']} fail"
    ]
    for check in checks:
        line = f"{check['status'].upper():<4} {check['name']:<20} {check['summary']}"
        if check.get("remediation"):
            line = f"{line} Fix: {check['remediation']}"
        lines.append(line)
    _emit(args.format, text_lines=lines, payload=payload)
    return 0 if payload["ok"] else 1


def cmd_plan(args: argparse.Namespace) -> int:
    export = _require_export(args.existing_export)
    overlay = Path(args.local_overlay) if args.local_overlay else None
    try:
        plan = build_merge_plan(export, overlay_path=overlay, full_reference=args.full_reference, private_output=args.private_output)
    except AppleTextError as exc:
        _fail(str(exc), code=2)
    payload = plan_to_json(plan)
    _emit(args.format, text_lines=format_plan(plan) or ["No changes."], payload=payload)
    return 0


def cmd_render(args: argparse.Namespace) -> int:
    export = _require_export(args.existing_export)
    overlay = Path(args.local_overlay) if args.local_overlay else None
    output = Path(args.output)
    try:
        render_merged_plist(export, output, overlay_path=overlay, full_reference=args.full_reference, private_output=args.private_output)
    except AppleTextError as exc:
        _fail(str(exc), code=2)
    sys.stdout.write(f"{output}\n")
    return 0


def cmd_stage(args: argparse.Namespace) -> int:
    export = _require_export(args.existing_export)
    overlay = Path(args.local_overlay) if args.local_overlay else None
    try:
        result = stage_import(
            export,
            apply=args.apply,
            overlay_path=overlay,
            open_ui=args.open_ui and args.apply,
            full_reference=args.full_reference,
            private_output=args.private_output,
        )
    except AppleTextError as exc:
        _fail(str(exc), code=1)
    lines = list(result["plan"])
    if result["dry_run"]:
        lines.append("dry-run: no files written")
    else:
        lines.append(f"staged: {result['staged']}")
        lines.append("Drag the staged plist into System Settings → Keyboard → Text Replacements.")
    _emit(args.format, text_lines=lines, payload=result)
    return 0


def cmd_rollback(args: argparse.Namespace) -> int:
    backup = Path(args.backup) if args.backup else None
    try:
        result = rollback_stage(backup, open_ui=args.open_ui)
    except AppleTextError as exc:
        _fail(str(exc), code=1)
    _emit(
        args.format,
        text_lines=[f"restaged {result['export']}", "Drag the restaged plist into Text Replacements."],
        payload=result,
    )
    return 0


def cmd_open_ui(_args: argparse.Namespace) -> int:
    try:
        staged = latest_staged_dir()
    except AppleTextError as exc:
        _fail(str(exc), code=1)
    open_staging_surfaces(staged)
    apple_named = staged / "Text Substitutions.plist"
    import_plist = staged / "property list.plist"
    target = apple_named if apple_named.is_file() else import_plist
    sys.stdout.write(f"opened {staged}\n")
    if target.is_file():
        sys.stdout.write(f"Drag {target.name} onto Text Replacements.\n")
    return 0


def cmd_shortcuts_plan(args: argparse.Namespace) -> int:
    try:
        payload = recipe_plan()
    except AppleTextError as exc:
        _fail(str(exc), code=2)
    lines = [f"{item['name']}: {item['id']}" for item in payload["recipes"]]
    _emit(args.format, text_lines=lines, payload=payload)
    return 0


def cmd_shortcuts_export(args: argparse.Namespace) -> int:
    destination = Path(args.output) if args.output else default_state_path() / "shortcut-exports"
    payload: dict[str, Any] = {"dry_run": not args.apply, "destination": str(destination)}
    if args.apply:
        export_describe_prompts(destination)
        payload["wrote"] = True
    _emit(
        args.format,
        text_lines=[
            f"{'dry-run ' if not args.apply else ''}export prompts to {destination}",
            "Build Shortcuts in Apple Shortcuts. Do not compile unofficial Shortcut binaries.",
        ],
        payload=payload,
    )
    return 0


def cmd_shortcuts_sync(args: argparse.Namespace) -> int:
    overlay = Path(args.local_overlay) if args.local_overlay else None
    destination = Path(args.destination) if args.destination else None
    try:
        result = sync_public_registry(
            apply=args.apply,
            destination=destination,
            overlay_path=overlay,
        )
    except AppleTextError as exc:
        message = str(exc)
        code = 1 if "unavailable" in message.lower() or "macos" in message.lower() else 2
        _fail(message, code=code)
    prefix = "dry-run " if result["dry_run"] else ""
    _emit(
        args.format,
        text_lines=[f"{prefix}sync {result['entryCount']} public entries to {result['destination']}"],
        payload=result,
    )
    return 0


def _require_export(value: str | None) -> Path:
    if not value:
        _fail("Provide --existing-export with a user-dragged Apple Text Replacement plist.")
    return Path(value)


def _add_format(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--format", choices=("text", "json"), default="text")


def _add_overlay(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--local-overlay", help="Local overlay JSON (mode 0600)")


def _add_reference_profile(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--full-reference", action="store_true", help="Add optional ;hN reference pages")
    parser.add_argument("--private-output", action="store_true", help="Allow private reference values in local output")


def cmd_list(args: argparse.Namespace) -> int:
    catalog = load_catalog()
    overlay = load_overlay(Path(args.local_overlay) if args.local_overlay else None)
    payload = {"records": list_records(catalog, overlay), "count": len(catalog.expansions)}
    _emit(args.format, text_lines=[f"{row['trigger']}  {row['label']}" for row in payload["records"]], payload=payload)
    return 0


def cmd_show(args: argparse.Namespace) -> int:
    catalog = load_catalog()
    overlay = load_overlay(Path(args.local_overlay) if args.local_overlay else None)
    phrase = show_phrase(catalog, args.trigger, overlay, private_output=args.private_output)
    if args.copy:
        _copy_text(phrase)
    sys.stdout.buffer.write(phrase.encode("utf-8"))
    return 0


def cmd_help_index(args: argparse.Namespace) -> int:
    catalog = load_catalog()
    overlay = load_overlay(Path(args.local_overlay) if args.local_overlay else None)
    if args.full_reference:
        pages, manifest = compile_reference_pages(catalog.expansions, catalog.generated_help, overlay)
        if any(page["private"] for page in pages) and not args.private_output:
            _fail("full reference includes local values; pass --private-output")
        if args.format == "json":
            public_pages = [] if not args.private_output else pages
            safe = {**manifest, "pages": [{k: v for k, v in page.items() if k != "body"} for page in public_pages]}
            sys.stdout.write(json.dumps(safe, indent=2) + "\n")
            return 0
        sys.stdout.write("".join(page["body"] for page in pages if args.private_output or not page["private"]))
        return 0
    text = render_help_index(
        catalog.expansions,
        catalog.reserved,
        catalog.generated_help,
        overlay,
        reference_profile=False,
    )
    _emit(args.format, text_lines=[text.rstrip("\n")], payload={"help": text, "deviceChecked": False})
    return 0


def cmd_verify_export(args: argparse.Namespace) -> int:
    report = verify_export(Path(args.existing_export), Path(args.expected_import))
    _emit(args.format, text_lines=[json.dumps(report)], payload=report)
    return 0 if report["ok"] else 1


def _copy_text(phrase: str) -> None:
    import shutil
    import subprocess

    if sys.platform != "darwin" or shutil.which("pbcopy") is None:
        _fail("clipboard copy is available only on macOS with pbcopy", code=2)
    subprocess.run(["pbcopy"], input=phrase.encode("utf-8"), check=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="apple-text",
        description="Validate, plan, and stage Apple Text Replacement and Shortcuts expansions.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    validate = sub.add_parser("validate", help="Validate canonical registries")
    _add_format(validate)
    _add_overlay(validate)
    validate.set_defaults(func=cmd_validate)

    doctor = sub.add_parser("doctor", help="Report registry, overlay, Shortcuts, and iCloud posture")
    _add_format(doctor)
    doctor.set_defaults(func=cmd_doctor)

    plan = sub.add_parser("plan", help="Preview a redacted merge against an Apple-exported plist")
    _add_format(plan)
    _add_overlay(plan)
    _add_reference_profile(plan)
    plan.add_argument("--existing-export", help="User-dragged Apple Text Replacement plist")
    plan.set_defaults(func=cmd_plan)

    render = sub.add_parser("render", help="Write a merged import plist without opening System Settings")
    _add_overlay(render)
    _add_reference_profile(render)
    render.add_argument("--existing-export", required=True)
    render.add_argument("--output", required=True)
    render.set_defaults(func=cmd_render)

    stage = sub.add_parser("stage", help="Preview or write backup plus staged import artifacts")
    _add_format(stage)
    _add_overlay(stage)
    _add_reference_profile(stage)
    stage.add_argument("--existing-export")
    stage.add_argument("--apply", action="store_true", help="Write staging artifacts (default is dry-run)")
    stage.add_argument("--open-ui", action="store_true", help="Open Finder and Keyboard settings on apply")
    stage.set_defaults(func=cmd_stage)

    rollback = sub.add_parser("rollback", help="Restage the pre-apply export for drag-import")
    _add_format(rollback)
    rollback.add_argument("--backup", help="Backup directory containing the original export")
    rollback.add_argument("--open-ui", action="store_true")
    rollback.set_defaults(func=cmd_rollback)

    open_ui = sub.add_parser("open-ui", help="Open the latest staged plist and Keyboard Text Replacements")
    open_ui.set_defaults(func=cmd_open_ui)

    shortcuts_plan = sub.add_parser("shortcuts-plan", help="Print Shortcut recipes and Describe-a-Shortcut prompts")
    _add_format(shortcuts_plan)
    shortcuts_plan.set_defaults(func=cmd_shortcuts_plan)

    shortcuts_export = sub.add_parser("shortcuts-export", help="Write Describe-a-Shortcut prompt files")
    _add_format(shortcuts_export)
    shortcuts_export.add_argument("--output", help="Directory for prompt files")
    shortcuts_export.add_argument("--apply", action="store_true")
    shortcuts_export.set_defaults(func=cmd_shortcuts_export)

    shortcuts_sync = sub.add_parser("shortcuts-sync", help="Copy the public Shortcut dictionary to iCloud Drive")
    _add_format(shortcuts_sync)
    _add_overlay(shortcuts_sync)
    shortcuts_sync.add_argument("--destination", help="Override iCloud registry path")
    shortcuts_sync.add_argument("--apply", action="store_true")
    shortcuts_sync.set_defaults(func=cmd_shortcuts_sync)

    listing = sub.add_parser("list", help="List redacted replacement records")
    _add_format(listing)
    _add_overlay(listing)
    listing.set_defaults(func=cmd_list)

    show = sub.add_parser("show", help="Show one phrase without evaluating it")
    _add_overlay(show)
    show.add_argument("trigger")
    show.add_argument("--private-output", action="store_true")
    show.add_argument("--copy", action="store_true", help="Copy the selected phrase with pbcopy")
    show.set_defaults(func=cmd_show)

    help_index = sub.add_parser("help", help="Show the generated replacement index")
    _add_format(help_index)
    _add_overlay(help_index)
    help_index.add_argument("--full-reference", action="store_true")
    help_index.add_argument("--private-output", action="store_true")
    help_index.set_defaults(func=cmd_help_index)

    verify = sub.add_parser("verify-export", help="Compare a fresh export with a staged import")
    _add_format(verify)
    verify.add_argument("--existing-export", required=True)
    verify.add_argument("--expected-import", required=True)
    verify.set_defaults(func=cmd_verify_export)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
