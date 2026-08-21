#!/usr/bin/env bash
# Local-only: compare tracked aliases vs HISTFILE command *tokens*.
# Writes gitignored local/zsh-alias-usage.txt. Never prints command arguments.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ALIASES_FILE="${1:-$REPO_DIR/rig/home/dot_zsh/aliases.zsh}"
HIST_PATH="${HISTFILE:-$HOME/.zsh_history}"
OUTPUT_DIR="$REPO_DIR/local"
OUTPUT_FILE="$OUTPUT_DIR/zsh-alias-usage.txt"

[[ -f $ALIASES_FILE ]] || {
  echo "missing aliases file: $ALIASES_FILE" >&2
  exit 1
}

mkdir -p "$OUTPUT_DIR"

python3 - "$ALIASES_FILE" "$HIST_PATH" "$OUTPUT_FILE" <<'PY'
from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path

aliases_path, hist_path, out_path = map(Path, sys.argv[1:4])

defined: list[str] = []
alias_name = re.compile(r"\balias\s+([A-Za-z0-9_.+-]+)=")
for line in aliases_path.read_text(encoding="utf-8").splitlines():
    if line.lstrip().startswith("#"):
        continue
    defined.extend(alias_name.findall(line))

hist_counts: Counter[str] = Counter()
if hist_path.is_file():
    text = hist_path.read_bytes().decode("utf-8", errors="replace")
    entries: list[str] = []
    buf: list[str] = []
    for line in text.splitlines():
        if line.startswith(": ") and ";" in line[:48]:
            if buf:
                entries.append("\n".join(buf))
            buf = [line.split(";", 1)[1]]
        elif buf:
            buf.append(line)
        elif line.strip():
            entries.append(line)
    if buf:
        entries.append("\n".join(buf))

    env_assign = re.compile(
        r"^[A-Za-z_][A-Za-z0-9_]*=(?:'[^']*'|\"[^\"]*\"|[^\s;]+)\s+"
    )
    wrapper = re.compile(r"^(sudo|noglob|command|builtin|nocorrect|time)\s+")
    for entry in entries:
        s = entry.strip()
        if not s:
            continue
        while True:
            m = env_assign.match(s)
            if not m:
                break
            s = s[m.end() :]
        s = wrapper.sub("", s, count=1)
        s = s.split("|", 1)[0].split("&&", 1)[0].split(";", 1)[0].strip()
        if not s:
            continue
        cmd = s.split()[0].strip("'\"")
        if "/" in cmd:
            cmd = Path(cmd).name
        if cmd and cmd not in {"export", "unset", "\\"}:
            hist_counts[cmd] += 1

defined_hits = [(name, hist_counts.get(name, 0)) for name in defined]
defined_hits.sort(key=lambda item: (-item[1], item[0]))
unused = [name for name, n in defined_hits if n == 0]
used = [(name, n) for name, n in defined_hits if n > 0]

skip_suggest = {
    "cd", "for", "if", "then", "else", "fi", "do", "done", "print", "printf",
    "echo", "read", "set", "source", ".", "bash", "zsh", "exec", "exit",
    "return", "true", "false", "which", "where", "type", "whence",
}
# tokens already covered by a tracked alias or that *are* the alias
covered = set(defined)
suggestions = [
    (tok, n)
    for tok, n in hist_counts.most_common(80)
    if n >= 8 and tok not in covered and tok not in skip_suggest and not tok.isdigit()
]

lines = [
    "# Redacted zsh alias usage (command tokens only; no arguments)",
    f"# aliases: {aliases_path}",
    f"# history: {hist_path if hist_path.is_file() else 'missing'}",
    f"# history tokens counted: {sum(hist_counts.values())}",
    "",
    "[used aliases]",
]
if used:
    lines.extend(f"{n:6d}  {name}" for name, n in used)
else:
    lines.append("(none)")
lines.extend(["", "[unused aliases]"])
if unused:
    lines.extend(f"     0  {name}" for name in unused)
else:
    lines.append("(none)")
lines.extend(["", "[frequent tokens without a tracked alias (count >= 8)]"])
if suggestions:
    lines.extend(f"{n:6d}  {tok}" for tok, n in suggestions)
else:
    lines.append("(none)")
lines.append("")
out_path.write_text("\n".join(lines), encoding="utf-8")
print(f"Wrote {out_path}")
PY
