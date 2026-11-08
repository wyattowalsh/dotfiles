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
uv run python - "$plan_json" <<'PY'
import json
import sys

raw = sys.argv[1]
assert "100 Example" not in raw
assert "Example Way" not in raw
plan = json.loads(raw)
kinds = {(item["kind"], item["trigger"]) for item in plan["operations"]}
assert ("PRESERVE", "") in kinds or plan["preservedUnrelated"] >= 1, plan
assert ("CONFLICT", "em-") in kinds, plan
assert ("CONFLICT", "myEn") in kinds, plan
assert ("MIGRATE", "aiaudit") in kinds, plan
assert not any(item["trigger"] == "myphone" and item["kind"] == "RETIRE" for item in plan["operations"])
assert "555-0199" not in raw
print("plan-ok")
PY

rendered="$TMP/merged.plist"
"$CLI" render --existing-export "$FIXTURE/export.plist" --output "$rendered" >/dev/null
uv run python - "$rendered" <<'PY'
import plistlib
import sys
from pathlib import Path

entries = plistlib.loads(Path(sys.argv[1]).read_bytes())
triggers = {item["shortcut"] for item in entries}
assert ";gh" in triggers
assert "mygh" in triggers
assert "myphone" in triggers, "divergent predecessor must be preserved"
assert "keepme" in triggers
assert "em-" in triggers
assert "aiaudit" not in triggers
print("render-ok")
PY

"$CLI" stage --existing-export "$FIXTURE/export.plist" --format json >/dev/null || fail "stage dry-run failed"
"$CLI" stage --existing-export "$FIXTURE/export.plist" --apply --format json >/dev/null || fail "stage apply failed"
cleanup="$(
  uv run python - "$DOTFILES_APPLE_TEXT_STATE" <<'PY'
from pathlib import Path
import sys

state = Path(sys.argv[1])
cleanup_matches = sorted(state.glob("staged-imports/*/CLEANUP.md"))
apple_named = sorted(state.glob("staged-imports/*/Text Substitutions.plist"))
legacy_named = sorted(state.glob("staged-imports/*/property list.plist"))
if not cleanup_matches:
    raise SystemExit("missing CLEANUP.md")
if not apple_named:
    raise SystemExit("missing Text Substitutions.plist")
if not legacy_named:
    raise SystemExit("missing property list.plist")
print(cleanup_matches[0])
PY
)"
uv run python - "$cleanup" <<'PY' || fail "cleanup notes missing migrate leftover"
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
assert "`aiaudit`" in text, text
assert "migrated" in text, text
assert "`myEn`" not in text
print("cleanup-ok")
PY

dest="$TMP/icloud/Shortcuts/AppleText/registry.json"
"$CLI" shortcuts-sync --destination "$dest" --apply --format json >/dev/null
uv run python - "$dest" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
blob = json.dumps(payload)
assert "myaddr" not in payload["entries"]
assert ";addr" not in payload["entries"]
assert "100 Example" not in blob
assert ";gh" in payload["entries"]
assert "mygh" not in payload["entries"]
assert "compose.ai-deep-research" in payload["entries"]
print("registry-ok")
PY

"$CLI" shortcuts-plan --format json >/dev/null || fail "shortcuts-plan failed"
uv run python - "$ROOT/rig/home/private_dot_config/apple-text/shortcuts.json" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
blob = json.dumps(payload)
assert "AgentsText" not in blob
assert "Shortcuts/AppleText/registry.json" in blob
print("icloud-path-ok")
PY
dup="$TMP/dup.plist"
uv run python - "$dup" <<'PY'
import plistlib
import sys
from pathlib import Path

Path(sys.argv[1]).write_bytes(
    plistlib.dumps(
        [
            {"shortcut": "mygh", "phrase": "one"},
            {"shortcut": "mygh", "phrase": "two"},
        ],
        fmt=plistlib.FMT_XML,
    )
)
PY
if "$CLI" plan --existing-export "$dup" --format json >/dev/null 2>"$TMP/dup.err"; then
  fail "duplicate export triggers should fail"
fi
uv run python - "$TMP/dup.err" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
assert "duplicate triggers" in text, text
print("dup-ok")
PY
doctor_json="$("$CLI" doctor --format json)"
uv run python - "$doctor_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
names = {item["name"] for item in payload["checks"]}
for name in ("live-text-library", "live-leftovers", "live-shortcuts", "icloud-registry"):
    assert name in names, names
print("doctor-ok")
PY
uv run python - "$doctor_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
for item in payload["checks"]:
    summary = item.get("summary", "").lower()
    if item["status"] == "ok" and "skipped" in summary:
        raise SystemExit("skipped check reported passed")
    if item["name"] in {"live-text-library", "live-leftovers"} and item["status"] != "skipped":
        raise SystemExit("live check not skipped")
print("skipped-ok")
PY

TMP_APPLE="$TMP" uv run python "$ROOT/checks/apple_text_regress.py"

help_a="$("$CLI" help --format text)"
help_b="$("$CLI" help --format text)"
[[ "$help_a" == "$help_b" ]] || fail "help index is not deterministic"
uv run python - "$help_a" <<'PY'
import sys
text = sys.argv[1]
for banned in ("100 Example", "555-0199"):
    if banned in text:
        raise SystemExit("help leaked a local value")
for required in (";pnl", ";panel is reserved", "not a modal command language", "No universal backslash"):
    if required not in text:
        raise SystemExit("help missing required wording")
print("help-ok")
PY

if "$CLI" help --full-reference --format text >"$TMP/full-public.txt" 2>"$TMP/full-public.err"; then
  fail "full reference exposed local pages without --private-output"
fi
if grep -q "100 Example" "$TMP/full-public.txt" || grep -q "555-0199" "$TMP/full-public.txt"; then
  fail "refused full reference still printed local values"
fi
"$CLI" help --full-reference --private-output --format json >"$TMP/full-private.json"
uv run python - "$TMP/full-private.json" <<'PY'
import json
import sys
from pathlib import Path
report = json.loads(Path(sys.argv[1]).read_text())
if report.get("missing"):
    raise SystemExit(report["missing"])
if len(report["covered"]) != len(set(report["covered"])):
    raise SystemExit("duplicate reference coverage")
print("reference-ok")
PY

if "$CLI" stage --existing-export "$FIXTURE/export.plist" --full-reference --format json >"$TMP/reference-refused.out" 2>"$TMP/reference-refused.err"; then
  fail "reference profile accepted without private-output authorization"
fi
if grep -q "100 Example\|555-0199" "$TMP/reference-refused.out" "$TMP/reference-refused.err"; then
  fail "refused reference profile leaked local values"
fi
"$CLI" stage --existing-export "$FIXTURE/export.plist" --full-reference --private-output --apply --format json >"$TMP/reference-stage.json"
uv run python - "$TMP/reference-stage.json" <<'PY'
import json
import plistlib
import sys
from pathlib import Path
result = json.loads(Path(sys.argv[1]).read_text())
staged = Path(result["staged"])
items = plistlib.loads(Path(result["importPlist"]).read_bytes())
if ";help" not in {row["shortcut"] for row in items} or not any(row["shortcut"].startswith(";h") for row in items):
    raise SystemExit("generated profile omitted installable entries")
if not (staged / "references.json").is_file() or not (staged / "REFERENCES.md").is_file():
    raise SystemExit("reference manifest or guide missing")
if result["desiredCount"] <= 52 or result["baseCount"] != 51:
    raise SystemExit("profile counts incorrect")
print("reference-stage-ok")
PY

"$CLI" show ';todo' >"$TMP/todo.out"
"$CLI" show ';done' >"$TMP/done.out"
"$CLI" show ';sig' >"$TMP/sig.out"
if "$CLI" show ';todo' --format json >"$TMP/show-json.out" 2>"$TMP/show-json.err"; then
  fail "show accepted misleading JSON mode"
fi
uv run python - "$TMP/todo.out" "$TMP/done.out" "$TMP/sig.out" <<'PY'
from pathlib import Path
import sys
todo, done, sig = (Path(item).read_bytes() for item in sys.argv[1:])
if todo != b"- [ ] " or done != b"- [x] ":
    raise SystemExit("task phrase bytes changed")
if b"\n" not in sig or sig.endswith(b"\n"):
    raise SystemExit("signature bytes changed")
print("phrase-bytes-ok")
PY

list_json="$("$CLI" list --format json)"
uv run python - "$list_json" <<'PY'
import json
import sys
raw = sys.argv[1]
if "100 Example" in raw or "555-0199" in raw:
    raise SystemExit("list leaked a local value")
payload = json.loads(raw)
if payload["count"] != 51:
    raise SystemExit(payload["count"])
if any("phrase" in row for row in payload["records"]):
    raise SystemExit("list JSON contains phrase bodies")
print("list-ok")
PY

"$CLI" verify-export --existing-export "$rendered" --expected-import "$rendered" --format json >"$TMP/verify.json"
uv run python - "$TMP/verify.json" <<'PY'
import json
import sys
from pathlib import Path
raw = Path(sys.argv[1]).read_text()
if "100 Example" in raw or "555-0199" in raw:
    raise SystemExit("verify report leaked a phrase")
report = json.loads(raw)
if not report["ok"] or report["deviceChecked"] is not False:
    raise SystemExit(report)
print("verify-ok")
PY

uv run python - "$TMP/partial-overlay.json" <<'PY'
import json
import os
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(json.dumps({"version": 2, "values": {"home_address": "100 Example Way"}, "overrides": {}}) + "\n")
os.chmod(path, 0o600)
PY
missing_plan="$(DOTFILES_APPLE_TEXT_OVERLAY="$TMP/partial-overlay.json" "$CLI" plan --existing-export "$FIXTURE/export.plist" --format json)"
uv run python - "$missing_plan" <<'PY'
import json
import sys
raw = sys.argv[1]
if "555-0199" in raw or "100 Example" in raw:
    raise SystemExit("unresolved plan leaked a local value")
plan = json.loads(raw)
kinds = {item["kind"] for item in plan["operations"]}
if plan.get("complete") is not False or "UNRESOLVED" not in kinds:
    raise SystemExit(plan)
print("unresolved-ok")
PY

"$CLI" rollback --format json >/dev/null || fail "rollback failed"
uv run python - "$DOTFILES_APPLE_TEXT_STATE" "$FIXTURE/export.plist" <<'PY'
import hashlib
import json
import sys
from pathlib import Path
state = Path(sys.argv[1])
transaction = json.loads((state / "transaction.json").read_text())
staged = sorted((state / "staged-imports").glob("rollback-*"))
if not staged:
    raise SystemExit("missing rollback stage")
restored = next(path for path in staged[-1].iterdir() if path.suffix == ".plist")
source = Path(sys.argv[2]).read_bytes()
if restored.read_bytes() != source:
    raise SystemExit("rollback bytes differ")
if hashlib.sha256(source).hexdigest() != transaction["backupSha256"]:
    raise SystemExit("manifest sha differs")
print("rollback-ok")
PY

uv run python - "$DOTFILES_APPLE_TEXT_STATE" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1]) / "transaction.json"
payload = json.loads(path.read_text())
payload["backupSha256"] = "0" * 64
path.write_text(json.dumps(payload))
PY
if "$CLI" rollback --format json >/dev/null 2>"$TMP/rollback-bad.err"; then
  fail "rollback accepted a mismatched manifest sha"
fi
grep -q "do not match" "$TMP/rollback-bad.err" || fail "rollback mismatch was not explained"
printf 'rollback-mismatch-ok\n'

before="$(find "$DOTFILES_APPLE_TEXT_STATE/backups" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
"$CLI" stage --existing-export "$FIXTURE/export.plist" --apply --format json >/dev/null
"$CLI" stage --existing-export "$FIXTURE/export.plist" --apply --format json >/dev/null
after="$(find "$DOTFILES_APPLE_TEXT_STATE/backups" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
if [[ "$after" -lt $((before + 2)) ]]; then
  fail "staging reused a backup directory"
fi
printf 'unique-stage-ok\n'

ln -s "$FIXTURE/export.plist" "$TMP/export-link.plist"
if "$CLI" stage --existing-export "$TMP/export-link.plist" --apply --format json >/dev/null 2>"$TMP/link.err"; then
  fail "symlink export was staged"
fi
grep -q "regular file" "$TMP/link.err" || fail "symlink rejection was not explained"
printf 'symlink-ok\n'

uv run python - "$DOTFILES_APPLE_TEXT_STATE" <<'PY' &
import fcntl
import time
from pathlib import Path
import sys
state = Path(sys.argv[1])
handle = (state / "stage.lock").open("a", encoding="utf-8")
fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
time.sleep(20)
PY
lock_pid=$!
sleep 0.3
if "$CLI" stage --existing-export "$FIXTURE/export.plist" --apply --format json >/dev/null 2>"$TMP/lock.err"; then
  kill "$lock_pid" 2>/dev/null || true
  wait "$lock_pid" 2>/dev/null || true
  fail "concurrent stage should fail"
fi
kill "$lock_pid" 2>/dev/null || true
wait "$lock_pid" 2>/dev/null || true
grep -q "another staging transaction" "$TMP/lock.err" || fail "lock contention was not explained"
printf 'lock-ok\n'

uv run python - "$DOTFILES_APPLE_TEXT_STATE" <<'PY'
import stat
import sys
from pathlib import Path
state = Path(sys.argv[1])
for path in state.rglob("*"):
    mode = stat.S_IMODE(path.stat().st_mode)
    expected = 0o700 if path.is_dir() else 0o600
    if mode != expected:
        raise SystemExit(f"mode {oct(mode)} on {path}")
print("mode-ok")
PY

(
  cd "$ROOT"
  just apple-text show ';pnl' >"$TMP/pnl.out"
)
grep -q . "$TMP/pnl.out" || fail "just did not forward ;pnl"
uv run python - "$TMP/pwn-trigger" "$TMP/pwned" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text(";$(touch " + sys.argv[2] + ")")
PY
pwn_trigger="$(cat "$TMP/pwn-trigger")"
rm -f "$TMP/pwned"
set +e
(cd "$ROOT" && just apple-text show "$pwn_trigger" >/dev/null 2>"$TMP/adv.err")
adv_status=$?
set -e
if [[ -e "$TMP/pwned" ]]; then
  fail "just evaluated a trigger as shell"
fi
if [[ "$adv_status" -eq 0 ]]; then
  fail "adversarial trigger was treated as a real record"
fi
printf 'just-forward-ok\n'
printf 'apple-text-test: ok\n'
