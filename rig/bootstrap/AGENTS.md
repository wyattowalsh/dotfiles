# AGENTS

## Scope

| Script | Role |
| --- | --- |
| `rig/bootstrap/macos.sh` | macOS full-rig bootstrap |
| `rig/bootstrap/linux.sh` | Debian/Ubuntu bootstrap (root `setup.sh` is a thin wrapper) |
| `rig/bootstrap/dev-env.sh` | Locate wyattowalsh/agents (`_is_agents_repo` must match agents `locate.sh`) and exec `scripts/bootstrap-dev-env.sh` |

`just bootstrap` dispatches: Darwin → `macos.sh`, Linux → `linux.sh`. `just bootstrap-dev` with empty args injects `--dry-run` (justfile).

## Path contract

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RIG_DIR="$REPO_ROOT/rig"
```

Machine paths: `$RIG_DIR/{brew,darwin,home,dots}`.

## macOS behavior

- **Default:** dry-run preview when neither `--dry-run` nor `--apply` is passed
- **Apply:** flock (mkdir fallback); `sudo -v` fail-fast keepalive; requires `rig/darwin/flake.lock`; creates missing parent directories for nested symlink targets; refuses to replace non-symlink home targets
- **Flags:** `--verbose`, `--no-upgrade` (brew bundle first-restore safety), `--with-dev-env`, `--require-dev-env`. `--with-dev-env` always passes `--skip-mcphub`.
- **Phases:** preflight → sudo keepalive (apply) → Xcode CLT wait → brew/just/nix/chezmoi → OMZ + p10k → Brewfile → **symlinks from `rig/dots/`** → Chezmoi → first-run Atuin import if the history db is missing → **Kopia nightly LaunchAgent** (when `rig/home/dot_local/bin/executable_kopia-nightly` exists) → nix-darwin → optional `dev-env.sh`
- **`nix_darwin_command`:** use `darwin-rebuild` if present; else pin from `flake.lock` — `locked.owner`/`repo`/`rev` **or** tarball `locked.url` archive SHA (`…/archive/<rev>.tar.gz`) plus `original.owner`/`repo`

Does not vendor AI harness/MCP configs or build docs. Agent stack is `just bootstrap-dev` (or `--with-dev-env`). Does not append to shell RC files.

## Linux behavior

- **Mutate by default.** No `--apply` flag. Preview with `--dry-run`; verify-only with `--smoke-check`.
- `create_symlinks` runs **before** OMZ (`KEEP_ZSHRC=yes` must not plant a real `~/.zshrc`).
- nvm installer: `PROFILE=/dev/null` (do not append into a repo-symlinked `~/.zshrc`).
- `run_dev_env` captures wrapper `rc` with `set +e` (do not use `if bash …; then`; after a failed `if`, `$?` is 0). Apply fail-closes; dry-run warns and continues.
- Universal skills from `~/.agents/skills` include `~/.claude/skills` when `claude` is on PATH (also copilot/codex/gemini).
- `--help` / `-h` disables the EXIT trap and does **not** print the SUCCESS summary.

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
just bootstrap-dev            # justfile injects --dry-run
just bootstrap-dev --apply --home
./setup.sh --dry-run --verbose   # → rig/bootstrap/linux.sh (includes dev-env)
```
