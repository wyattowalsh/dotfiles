# AGENTS

## Scope

`bootstrap/macos.sh` — macOS full-rig bootstrap dispatcher invoked via `task bootstrap`.

## Behavior

- **Default:** dry-run preview when neither `--dry-run` nor `--apply` is passed
- **Apply:** requires `darwin/flake.lock`; refuses to replace non-symlink home targets
- **Phases:** Xcode CLT → brew/task/nix/chezmoi/pnpm → Brewfile → root symlinks → Chezmoi → nix-darwin

Does not install AI CLIs, skills, or build docs. See `setup.sh` for Linux AI bootstrap.

## Rules

- Preserve idempotency: check state before every mutating step
- `--dry-run` must not install packages, write links, or switch nix-darwin
- Start scripts with `set -euo pipefail`; quote paths
- Validate with `bash -n bootstrap/macos.sh` and `task check:shell`
- Document flag changes in `docs/content/docs/fresh-mac.mdx`

## Entrypoints

```bash
task bootstrap -- --dry-run
task bootstrap -- --apply
task bootstrap -- --verbose
```