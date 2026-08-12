# AGENTS — rig/

## Scope

Machine desired-state and bootstrap for this personal rig. Everything that **becomes the Mac** lives here.

| Path | Role |
| --- | --- |
| `rig/bootstrap/` | macOS + Linux bootstrap scripts |
| `rig/dots/` | Runtime files symlinked into `$HOME` |
| `rig/brew/` | Homebrew Bundle desired state |
| `rig/darwin/` | nix-darwin / Home Manager flake |
| `rig/home/` | Chezmoi source (templates + parity mirrors) |

## Path contract

- From scripts under `rig/bootstrap/`: `REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"`, `RIG_DIR="$REPO_ROOT/rig"`.
- Prefer `$RIG_DIR/{brew,darwin,home,dots}` for all machine paths.
- Repo process surfaces stay **outside** `rig/`: `docs/`, `checks/`, `openspec/`, `local/`, root `justfile` / `AGENTS.md` / `setup.sh`.

## Rules

- Do not reintroduce top-level `bootstrap/`, `dots/`, `brew/`, `darwin/`, or `home/` partitions.
- Nested `AGENTS.md` files here are thin; operator runbooks stay under `docs/content/docs/`.
- Validate path changes with `just check-shell`, `just check-zsh`, `just bootstrap --dry-run`.
