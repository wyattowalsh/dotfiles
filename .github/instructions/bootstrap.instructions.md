---
applyTo: "rig/bootstrap/**,setup.sh,checks/**,justfile"
---

@../../AGENTS.md

## Bootstrap focus

- Preserve idempotency: check state before mutating; refuse non-symlink clobber
- macOS: `rig/bootstrap/macos.sh` defaults to dry-run; `--apply` requires `rig/darwin/flake.lock`
- Linux: `setup.sh` supports `--dry-run`, `--verbose`, `--smoke-check` (→ `rig/bootstrap/linux.sh`)
- Path contract: `REPO_ROOT` + `RIG_DIR="$REPO_ROOT/rig"` from `rig/bootstrap/`
- Delegate complex logic to `checks/` scripts; keep justfile recipes thin

## Validate

```bash
just check-shell
just check
just smoke
```

Sync `docs/content/docs/fresh-mac.mdx` when bootstrap phases change.
