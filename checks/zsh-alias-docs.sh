#!/usr/bin/env bash
# CI-safe: every alias name= in aliases.zsh has a preceding #: description.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ALIASES_FILE="${1:-$REPO_DIR/rig/home/dot_zsh/aliases.zsh}"

[[ -f $ALIASES_FILE ]] || {
  echo "missing aliases file: $ALIASES_FILE" >&2
  exit 1
}

python3 - "$ALIASES_FILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
alias_re = re.compile(r"\balias\s+([A-Za-z0-9_.+-]+)=")
missing: list[str] = []
prev_desc = False
for i, line in enumerate(lines, start=1):
    stripped = line.strip()
    if stripped.startswith("#:"):
        prev_desc = True
        continue
    if stripped.startswith("#") or stripped == "":
        prev_desc = False
        continue
    if alias_re.search(line):
        if not prev_desc:
            names = ", ".join(alias_re.findall(line))
            missing.append(f"{path}:{i}: alias {names} lacks preceding #:")
        prev_desc = False
        continue
    prev_desc = False

if missing:
    print("zsh-alias-docs: missing #:", file=sys.stderr)
    print("\n".join(missing), file=sys.stderr)
    sys.exit(1)
print(f"zsh-alias-docs: ok ({path})")
PY
