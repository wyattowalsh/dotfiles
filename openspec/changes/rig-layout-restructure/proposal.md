# Change: rig layout restructure

## Why

Top-level mixed machine desired-state (`bootstrap`, `dots`, `brew`, `darwin`, `home`) with repo process surfaces (`docs`, `checks`, tooling). Grouping machine SSOT under `rig/` yields a quieter root and a clearer two-click mental model.

## What changes

- Move `bootstrap/`, `dots/`, `brew/`, `darwin/`, `home/` under `rig/`
- Introduce canonical `REPO_ROOT` + `RIG_DIR` path contracts in bootstrap
- Rewire `justfile`, pre-commit globs, checks, AGENTS, docs, OpenSpec path strings
- Keep root `AGENTS.md`, `justfile`, thin `setup.sh`, `docs/`, `checks/`, `openspec/`, `local/`

## Non-goals

- Behavior changes to freshen, Brewfile contents, or nix modules
- Renaming `checks/` → `tests/`
- Parent name `dotfiles/` (avoids nested `dotfiles/dotfiles/`)

## Validation

- `just check-shell`, `just check-zsh`, `just check-freshen`, `just docs-ci`, `just smoke`
- `just bootstrap --dry-run`
- Stale-path freeze via `checks/stale-path-freeze.sh` on `just check`
- Operator re-link: `just bootstrap --apply` so live home points at `rig/dots/*`
