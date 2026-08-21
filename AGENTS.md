# AGENTS

## Purpose
This repository is a **personal public** dotfiles SSOT for the `w4w-mbp` rig (username `ww`). It captures curated desired state for shell, editor, git, Homebrew, nix-darwin, and Chezmoi-managed home config. Treat the live Mac as inventory (`just inventory-redacted` → gitignored `local/`), promote intentional changes into tracked files, and keep secrets out of git. Host slug, git identity, and nix user paths are intentional personal markers — not secrets.

**AI harness, MCP servers, and agent client configs** live in [wyattowalsh/agents](https://github.com/wyattowalsh/agents) — not here. This repo may document env var *names* (`.env.example`) only.

## Agent instruction surface
- **SSOT for all coding agents:** this file (`AGENTS.md`). Do not reintroduce per-vendor root stubs (`.claude/`, `GEMINI.md`, `CLAUDE.md`, etc.).
- Nested `*/AGENTS.md` files are thin subsystem contracts for agents; human runbooks live only under `docs/content/docs/`.
- Optional repo tooling under `.github/` (e.g. Copilot path instructions) may point here; they are not a second contract SSOT.

## Tooling conventions
- **Workflows:** `just` (`justfile`) — `just check`, `just ci`, `just docs-ci`, `just bootstrap --dry-run`. Brew owns the `just` binary (`terror/tap/just-lsp` is editor support only). Do **not** install `just` via mise. `go-task` is inventory-only — not a runner for this repo.
- **Toolchains:** `mise` is the version manager (Node/Python/pnpm/uv shims). Activate once from zshrc. Do not add a repo-root `mise.toml` / `.mise.toml`, and do not add mise `[tasks]` that duplicate just recipes. direnv owns env + `layout_uv` and must not call `use mise`.
- **Python:** use **uv** for any Python ops if/when scripts or tools require it (no repo `pyproject.toml` today).
- **Docs site:** `pnpm` inside `docs/` (see `just docs-*`).
- **Shell scripts:** `bash` with `set -euo pipefail` under `checks/` and `rig/bootstrap/`. Lint with ShellCheck; format with `shfmt -i 2 -ci -bn`; bash tests with Bats (`just check-bats`).

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
- `setup.sh` installs `@anthropic-ai/claude-code`, `@github/copilot`, and `@openai/codex` via npm when missing, and installs `github/gh-copilot` for `gh` when available. It does not install Gemini CLI.
- `setup.sh` maintains startup shim links for `claude`, `copilot`, and `codex` in `~/.local/bin`.
- `setup.sh` delegates the agent stack to `rig/bootstrap/dev-env.sh` → wyattowalsh/agents `scripts/bootstrap-dev-env.sh` with `--skip-mcphub`. Apply fails if the wrapper or installer fails. It does not run a hardcoded `npx skills add` skill list.
- Universal skills from `~/.agents/skills` are mirrored into per-agent skill dirs for installed CLIs (`copilot`, `codex`, `grok`, `opencode`) when that store exists.
- Do **not** add MCP JSON, client manifests, or harness configs to this repo — change `wyattowalsh/agents` instead.
- `setup.sh` skips `chsh` default-shell updates in Codespaces or non-interactive sessions.

## Bash safety conventions
- Start bash scripts with: `set -euo pipefail`.
- Verify required commands before use: `command -v <cmd> >/dev/null 2>&1`.
- Manage symlinks with replacement semantics: `ln -sfn <source> <target>`.
- Quote variable/path expansions.

## Justfile conventions
- Use `justfile` as the command runner; do not add a `Taskfile.yml`, Makefile, or mise `[tasks]` block.
- Keep just recipes thin and delegate complex shell logic to scripts under `checks/` or `rig/bootstrap/`.
- Recipes that may mutate state must provide a dry-run or preview path (e.g. `just bootstrap --dry-run`).
- Format the justfile with `just --unstable --fmt --check` (`just check-just-fmt`).

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
