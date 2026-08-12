# AGENTS

## Scope

| Script | Role |
| --- | --- |
| `rig/bootstrap/macos.sh` | macOS full-rig bootstrap (`just bootstrap`) |
| `rig/bootstrap/linux.sh` | Debian/Ubuntu bootstrap (root `setup.sh` is a thin wrapper) |

## Path contract

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RIG_DIR="$REPO_ROOT/rig"
```

Machine paths: `$RIG_DIR/{brew,darwin,home,dots}`.

## macOS behavior

- **Default:** dry-run preview when neither `--dry-run` nor `--apply` is passed
- **Apply:** requires `rig/darwin/flake.lock`; creates missing parent directories for nested symlink targets; refuses to replace non-symlink home targets
- **Flags:** `--verbose`, `--no-upgrade` (brew bundle first-restore safety)
- **Phases:** preflight → sudo keepalive (apply) → Xcode CLT wait → brew/just/nix/chezmoi → OMZ + p10k → Brewfile → **symlinks from `rig/dots/`** → Chezmoi → nix-darwin

Does not install AI harness/MCP configs or build docs. Does not append to shell RC files.

## Rules

- Preserve idempotency: check state before every mutating step
- `--dry-run` must not install packages, write links, or switch nix-darwin
- Start scripts with `set -euo pipefail`; quote paths
- Runtime home files live under `rig/dots/` (not repo root)
- Validate with `just check-shell`
- Document flag changes in `docs/content/docs/fresh-mac.mdx` / `linux-setup.mdx`

## Entrypoints

```bash
just bootstrap --dry-run
just bootstrap --apply --no-upgrade
./setup.sh --dry-run --verbose   # → rig/bootstrap/linux.sh
```
