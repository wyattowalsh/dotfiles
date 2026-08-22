#!/usr/bin/env bash
# Offline merge/validate coverage for Apple text expansions (no Apple DB writes).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/checks/apple-text.sh"
FIXTURE="$ROOT/checks/fixtures/apple-text"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export DOTFILES_APPLE_TEXT_OVERLAY="$FIXTURE/overlay.json"
export DOTFILES_APPLE_TEXT_STATE="$TMP/state"
export DOTFILES_APPLE_ICLOUD="$TMP/icloud"
export DOTFILES_APPLE_TEXT_SKIP_LIVE=1
mkdir -p "$DOTFILES_APPLE_ICLOUD"

fail() {
  printf 'apple-text-test: %s\n' "$*" >&2
  exit 1
}

"$CLI" validate --format json >/dev/null || fail "validate failed"

plan_json="$("$CLI" plan --existing-export "$FIXTURE/export.plist" --format json)"
python3 - "$plan_json" <<'PY'
import json
import sys

raw = sys.argv[1]
assert "100 Example" not in raw
assert "Example Way" not in raw
plan = json.loads(raw)
kinds = {(item["kind"], item["trigger"]) for item in plan["operations"]}
assert ("PRESERVE", "") in kinds or plan["preservedUnrelated"] >= 1, plan
assert ("RETIRE", "em-") in kinds, plan
assert ("MIGRATE", "myEn") in kinds, plan
assert not any(item["trigger"] == "myphone" and item["kind"] == "RETIRE" for item in plan["operations"])
print("plan-ok")
PY

rendered="$TMP/merged.plist"
"$CLI" render --existing-export "$FIXTURE/export.plist" --output "$rendered" >/dev/null
python3 - "$rendered" <<'PY'
import plistlib
import sys
from pathlib import Path

entries = plistlib.loads(Path(sys.argv[1]).read_bytes())
triggers = {item["shortcut"] for item in entries}
assert "mygh" in triggers
assert "myphone" in triggers, "unrelated live replacement must be preserved"
assert "em-" not in triggers
print("render-ok")
PY

"$CLI" stage --existing-export "$FIXTURE/export.plist" --format json >/dev/null || fail "stage dry-run failed"
"$CLI" stage --existing-export "$FIXTURE/export.plist" --apply --format json >/dev/null || fail "stage apply failed"
cleanup="$(
  python3 - "$DOTFILES_APPLE_TEXT_STATE" <<'PY'
from pathlib import Path
import sys

matches = sorted(Path(sys.argv[1]).glob("staged-imports/*/CLEANUP.md"))
if not matches:
    raise SystemExit("missing CLEANUP.md")
print(matches[0])
PY
)"
python3 - "$cleanup" <<'PY' || fail "cleanup notes missing migrate leftover"
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
assert "`myEn`" in text, text
assert "migrated" in text, text
print("cleanup-ok")
PY

dest="$TMP/icloud/Shortcuts/AppleText/registry.json"
"$CLI" shortcuts-sync --destination "$dest" --apply --format json >/dev/null
python3 - "$dest" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
assert "myaddr" not in payload["entries"]
assert "mygh" in payload["entries"]
assert "compose.ai-deep-research" in payload["entries"]
print("registry-ok")
PY

"$CLI" shortcuts-plan --format json >/dev/null || fail "shortcuts-plan failed"
doctor_json="$("$CLI" doctor --format json)"
python3 - "$doctor_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
names = {item["name"] for item in payload["checks"]}
for name in ("live-text-library", "live-leftovers", "live-shortcuts", "icloud-registry"):
    assert name in names, names
print("doctor-ok")
PY
printf 'apple-text-test: ok\n'
