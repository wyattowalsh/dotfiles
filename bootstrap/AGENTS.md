# AGENTS

## Scope
Bootstrap scripts and first-run orchestration.

## Rules
- Preserve idempotency: every mutating step checks current state first.
- Support `--dry-run`; dry-run must not install packages, write links, or start services.
- Keep shell scripts Bash-compatible and start with `set -euo pipefail`.
- Validate edits with `bash -n` and `shellcheck` when available.
- Prefer Taskfile entrypoints over ad hoc command documentation.

