---
applyTo: "bootstrap/**,setup.sh,checks/**,Taskfile.yml"
---

@../../AGENTS.md

## Bootstrap focus

- Preserve idempotency: check state before mutating; refuse non-symlink clobber
- macOS: `bootstrap/macos.sh` defaults to dry-run; `--apply` requires `darwin/flake.lock`
- Linux: `setup.sh` supports `--dry-run`, `--verbose`, `--smoke-check`
- Delegate complex logic to `checks/` scripts; keep Taskfile tasks thin

## Validate

```bash
task check:shell
task check
task smoke
```

Sync `docs/content/docs/fresh-mac.mdx` when bootstrap phases change.