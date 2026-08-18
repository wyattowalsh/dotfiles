# AGENTS

## Purpose
This repository is a **personal public** dotfiles SSOT for the `w4w-mbp` rig (username `ww`). It captures curated desired state for shell, editor, git, Homebrew, nix-darwin, and Chezmoi-managed home config. Treat the live Mac as inventory (`just inventory-redacted` → gitignored `local/`), promote intentional changes into tracked files, and keep secrets out of git. Host slug, git identity, and nix user paths are intentional personal markers — not secrets.

**AI harness, MCP servers, and agent client configs** live in [wyattowalsh/agents](https://github.com/wyattowalsh/agents) — not here. This repo may document env var *names* (`.env.example`) only.

## Agent instruction surface
- **SSOT for all coding agents:** this file (`AGENTS.md`). Do not reintroduce per-vendor root stubs (`.claude/`, `GEMINI.md`, `CLAUDE.md`, etc.).
- Nested `*/AGENTS.md` files are thin subsystem contracts for agents; human runbooks live only under `docs/content/docs/`.
- Optional repo tooling under `.github/` (e.g. Copilot path instructions) may point here; they are not a second contract SSOT.

## Tooling conventions
- **Workflows:** `just` (`justfile`) — `just check`, `just ci`, `just docs-ci`, `just bootstrap --dry-run`.
- **Python:** use **uv** for any Python ops if/when scripts or tools require it (no repo `pyproject.toml` today).
- **Docs site:** `pnpm` inside `docs/` (see `just docs-*`).
- **Shell scripts:** `bash` with `set -euo pipefail` under `checks/` and `rig/bootstrap/`.

## SSOT workflow
1. Run `just inventory-redacted` to refresh ignored `local/Brewfile.raw` and config-dir inventory.
2. Diff live vs repo (`cmp` for `rig/dots/zshrc`/`rig/dots/p10k.zsh` vs Chezmoi mirrors, `just home-diff`, `just brew-check`).
3. Promote curated changes into `rig/brew/Brewfile`, `rig/home/`, `rig/dots/`, and `rig/darwin/` as appropriate.
4. Validate with `just check` (and `just ci` / `just docs-ci` when docs or full CI parity matter) before `just bootstrap --apply` on macOS.

## Files overview
- `justfile`: canonical workflow runner (bootstrap, checks, docs, Brew, Darwin, inventory, secrets).
- `setup.sh`: thin wrapper → `rig/bootstrap/linux.sh` (Linux/Debian bootstrap).
- `rig/`: **machine desired-state + bootstrap** (all partitions that become the Mac).
  - `rig/bootstrap/`: platform bootstraps (`macos.sh`, `linux.sh`).
  - `rig/dots/`: tracked runtime files symlinked into `$HOME` (zshrc, p10k, gitconfig, …).
  - `rig/brew/`: curated Homebrew Bundle desired state (`Brewfile`, `exclude.txt`).
  - `rig/darwin/`: nix-darwin/Home Manager scaffold for Apple Silicon macOS.
  - `rig/home/`: Chezmoi-style home configuration templates + parity mirrors (includes headless Kopia nightly runner + LaunchAgent).
- `docs/`: internal Fumadocs operator documentation site (human runbook SSOT).
- `checks/`: validation and smoke-check scripts (`docs-`, `zsh-`, `freshen-`, `brew-` prefixes).
- `openspec/`: OpenSpec change notes for non-trivial workflow/public structure changes.
- `local/`: **ignored** redacted inventory and local research artifacts (never commit).
- `.env.example`: documented env var names for AI/MCP (values stay local).
- `.github/`: Copilot path instructions, LSP config, CI workflow (may reference `AGENTS.md`).
- `AGENTS.md`: repository conventions for humans and automation (this file).
- `LICENSE` / `README.md`: license + thin human entry.

## Path contract
- Bootstrap scripts resolve `REPO_ROOT` + `RIG_DIR="$REPO_ROOT/rig"` (never a single `..` from under `rig/`).
- Machine paths use `$RIG_DIR/{brew,darwin,home,dots}`.
- Checks stay top-level under `checks/` and resolve repo root with one `..`, then prefix `rig/`.

## `setup.sh` idempotency contract
- Running `./setup.sh` multiple times must be safe and produce the same final state.
- Check current state before mutating it, and skip steps that are already satisfied.
- Do not append duplicate config lines or create duplicate artifacts.
- Keep fail-fast behavior for required steps, while explicitly optional steps warn and continue.
- Run preflight checks before mutations; use `--smoke-check` for verification-only behavior.
- Guard mutating runs with a lock/concurrency check and emit structured exit summary counters.
- Use retry + backoff + command timeouts for network-sensitive operations.
- Use safer apt privilege handling: explicit privilege checks + `run_privileged` + noninteractive apt options.

## Linux AI bootstrap notes (CLIs only — configs in agents repo)
- `setup.sh` installs `@anthropic-ai/claude-code`, `@google/gemini-cli`, `@github/copilot`, and `@openai/codex` via npm when missing, and installs `github/gh-copilot` for `gh` when available.
- `setup.sh` maintains startup shim links for `claude`, `gemini`, `copilot`, and `codex` in `~/.local/bin`.
- `setup.sh` delegates the agent stack to `rig/bootstrap/dev-env.sh` → wyattowalsh/agents `scripts/bootstrap-dev-env.sh` with `--skip-mcphub`. Apply fails if the wrapper or installer fails. It does not run a hardcoded `npx skills add` skill list.
- Universal skills from `~/.agents/skills` are mirrored into per-agent skill dirs for installed CLIs when that store exists.
- Do **not** add MCP JSON, client manifests, or harness configs to this repo — change `wyattowalsh/agents` instead.
- `setup.sh` skips `chsh` default-shell updates in Codespaces or non-interactive sessions.

## Bash safety conventions
- Start bash scripts with: `set -euo pipefail`.
- Verify required commands before use: `command -v <cmd> >/dev/null 2>&1`.
- Manage symlinks with replacement semantics: `ln -sfn <source> <target>`.
- Quote variable/path expansions.

## Justfile conventions
- Use `justfile` as the command runner; do not add a `Taskfile.yml` or Makefile.
- Keep just recipes thin and delegate complex shell logic to scripts under `checks/` or `rig/bootstrap/`.
- Recipes that may mutate state must provide a dry-run or preview path (e.g. `just bootstrap --dry-run`).

## macOS full-rig conventions
- Treat the live Mac as inventory, not as a blob to commit.
- Curate Homebrew packages by intent before promoting them to `rig/brew/Brewfile`.
- Keep nix-darwin/Home Manager host-specific values in `rig/darwin/hosts/`.
- Keep portable home configuration in `rig/home/` and private values in local Chezmoi data or untracked overrides.

## No secrets policy
- Never commit passwords, tokens, API keys, private keys, or other secrets.
- Keep sensitive values in untracked local files or environment variables.

## Documentation maintenance
- Human operator runbooks: `docs/content/docs/` only (Fumadocs). Sidebar: `docs/content/docs/meta.json`. Hub cards: `docs/lib/hub-manifest.json` (parity via `just docs-hub-parity`).
- Nested `AGENTS.md` files are **agent contracts**, not operator prose — keep them rule-focused and point to docs for runbooks.
- Subsystem `README.md` files are **optional** and must stay thin (commands + pointers only); they are not a second runbook SSOT.
- `checks/` scripts use prefix naming (`docs-`, `zsh-`, `freshen-`, `brew-`, `kopia-`) instead of deep folders unless an explicit layout migration is approved.
- When changing justfile recipes, bootstrap phases, Brewfile groups, shell, or home layout — update the matching MDX page (and nested `AGENTS.md` if agent rules change) in the same change.
- AI harness docs point to `wyattowalsh/agents`; only env var **names** belong in dotfiles.
- Never paste `local/` inventory, secret values, or absolute `/Users/<name>/` paths into docs.
- Validate doc changes with `just docs-ci` and `just secrets-scan` before merge.

## Cursor Cloud specific instructions
The startup update script (see the Cloud Agent environment) installs `zsh`, `ripgrep`, `shellcheck`, `just` 1.39.0 (to `/usr/local/bin`), `uv` + `pre-commit`, and runs `pnpm -C docs install --frozen-lockfile`. Node/pnpm ship in the base image. After startup you can run everything below without extra PATH setup.

- **Canonical validation:** `just ci` (= `check` + `smoke` + `docs-ci`) — same command GitHub CI runs. `just check` is static-only; docs steps live in `just docs-ci`.
- **`just` version matters:** the `justfile` uses the `[working-directory: 'docs']` attribute, which needs `just >= 1.24`. Ubuntu's apt `just` (1.21) is too old and fails to parse the file — always use the pinned 1.39.0 the update script installs, not `apt install just`.
- **Docs site is the runnable app:** `pnpm -C docs dev` serves Fumadocs/Next.js 16 (Turbopack) at http://localhost:3000. Static build: `just docs-build` (output `docs/out`). Frozen install + typecheck + build + doc health checks run via `just docs-ci`.
- **Expected non-fatal warnings:** `just smoke` and `./setup.sh --dry-run` print `[WARN] ... symlink missing/not a symlink` for `$HOME` dotfiles and an `agents checkout not found` notice. This is normal on a cloud VM where the rig is not applied; both still exit 0. Do not try to "fix" these by creating symlinks.
- **Do not apply the rig here:** never run `./setup.sh` (non-dry-run) or `just bootstrap --apply` in the cloud VM — they mutate `$HOME`/system state for the real Mac/Linux rig. Use `--dry-run` to exercise the bootstrap path.
- **Optional linters:** `shellcheck` (for `just check-shell`) and `pre-commit` (for `just check-hooks`) are installed but the recipes skip gracefully if absent; `pre-commit` resolves via `/usr/local/bin` symlink to the `uv`-managed install in `~/.local/bin`.

### AI harness (wyattowalsh/agents) bootstrap
SSOT for the harness is [wyattowalsh/agents](https://github.com/wyattowalsh/agents); this repo only delegates via `rig/bootstrap/dev-env.sh` (`just bootstrap-dev`). It is **not** part of the update script (heavy second repo + optional). Provision on demand:

```bash
git clone --depth 1 https://github.com/wyattowalsh/agents.git ~/dev/projects/agents
uv sync --project ~/dev/projects/agents          # builds the wagents env (Python 3.13+, auto-provisioned)
just bootstrap-dev --apply --home                # projects repo + ~/.cursor harness surfaces (cloud profile auto --skip-mcphub)
```

Cloud-specific caveats found during setup:
- **Seed `~/.codex/config.toml` first** (`mkdir -p ~/.codex && : > ~/.codex/config.toml`). `scripts/sync_agent_stack.py` reads it unconditionally and crashes with `FileNotFoundError` on a machine without codex; an empty file parses fine.
- **`wagents` CLI is currently broken at agents HEAD** — `cannot import name 'web_app' from 'wagents.docs'` (`wagents/cli.py`). The `sync-repo`/`sync-home` projection (agents, hooks, rules, skill symlinks) and MCPHub are unaffected, but the `skills-preview` and `hooks` phases warn until this is fixed upstream. This is not a dotfiles bug.
- **MCPHub is opt-in and loopback-only.** `just bootstrap-dev --apply --mcphub` (or `bash ~/dev/projects/agents/scripts/mcphub/start-local-only.sh`) starts `npx @samanhappy/mcphub` on `127.0.0.1:46683`; it needs `~/dev/projects/agents/.env.mcphub` (gitignored) with local `ADMIN_PASSWORD`/`JWT_SECRET`/`MCPHUB_BEARER_TOKEN`. The running hub persists OAuth client state into `mcp/mcphub/mcp_settings.json`, so `generate_mcphub_settings.py --check` reports drift once the hub has run — expected, not source drift.
