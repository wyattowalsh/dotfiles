# AGENTS

## Purpose
This repository is a **private, personal, internal-only** dotfiles SSOT for the `w4w-mbp` rig (`/Users/ww`). It captures curated desired state for shell, editor, git, Homebrew, nix-darwin, and Chezmoi-managed home config. Treat the live Mac as inventory (`just inventory-redacted` → `local/`), promote intentional changes into tracked files, and keep secrets out of git.

**AI harness, MCP servers, and agent client configs** live in [wyattowalsh/agents](https://github.com/wyattowalsh/agents) — not here. This repo may document env var *names* (`.env.example`) only.

## SSOT workflow
1. Run `just inventory-redacted` to refresh ignored `local/Brewfile.raw` and config-dir inventory.
2. Diff live vs repo (`cmp` for `.zshrc`/`.p10k.zsh`, `just home-diff`, `just brew-check`).
3. Promote curated changes into `brew/Brewfile`, `home/`, root dotfiles, and `darwin/` as appropriate.
4. Validate with `just check` before `just bootstrap --apply` on macOS.

## Files overview
- `setup.sh`: main bootstrap entrypoint (should converge system state when re-run; supports `--dry-run`, `--verbose`, and `--smoke-check`).
- `justfile`: canonical workflow runner for bootstrap, checks, docs, Brew, Darwin, inventory, and secret scans.
- `bootstrap/`: macOS full-rig bootstrap scripts.
- `brew/`: curated Homebrew Bundle desired state and package notes.
- `darwin/`: nix-darwin/Home Manager scaffold for Apple Silicon macOS.
- `home/`: Chezmoi-style home configuration templates.
- `docs/`: internal Fumadocs documentation site.
- `checks/`: validation and smoke-check scripts invoked by justfile recipes.
- `openspec/`: OpenSpec change notes for non-trivial workflow/public structure changes.
- `.zshrc`: Zsh runtime configuration.
- `.p10k.zsh`: Powerlevel10k prompt configuration.
- `.gitconfig`: shared Git configuration defaults.
- `.ripgreprc`: default ripgrep options.
- `.editorconfig`: cross-editor formatting defaults.
- `.env.example`: documented env var names for AI/MCP (values stay local).
- `.github/lsp.json`: repository LSP configuration used by GitHub tooling.
- `.github/copilot-instructions.md`: repository instructions used by GitHub Copilot when editing **this repo**.
- `.claude/CLAUDE.md`: Claude hint for this repo (delegates to `AGENTS.md`).
- `AGENTS.md`: repository conventions for humans and automation.
- `GEMINI.md`: Gemini hint for this repo (delegates to `AGENTS.md`).
- `LICENSE`: licensing terms.

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
- `setup.sh` installs skills from `wyattowalsh/agents` via non-interactive `npx -y skills add --yes` when CLIs exist.
- Universal skills from `~/.agents/skills` are mirrored into per-agent skill dirs for installed CLIs.
- Do **not** add MCP JSON, client manifests, or harness configs to this repo — change `wyattowalsh/agents` instead.
- `setup.sh` skips `chsh` default-shell updates in Codespaces or non-interactive sessions.

## Bash safety conventions
- Start bash scripts with: `set -euo pipefail`.
- Verify required commands before use: `command -v <cmd> >/dev/null 2>&1`.
- Manage symlinks with replacement semantics: `ln -sfn <source> <target>`.
- Quote variable/path expansions.

## Justfile conventions
- Use `justfile` as the command runner; do not add a `Taskfile.yml` or Makefile.
- Keep just recipes thin and delegate complex shell logic to scripts under `checks/` or `bootstrap/`.
- Recipes that may mutate state must provide a dry-run or preview path (e.g. `just bootstrap --dry-run`).

## macOS full-rig conventions
- Treat the live Mac as inventory, not as a blob to commit.
- Curate Homebrew packages by intent before promoting them to `brew/Brewfile`.
- Keep nix-darwin/Home Manager host-specific values in `darwin/hosts/`.
- Keep portable home configuration in `home/` and private values in local Chezmoi data or untracked overrides.

## No secrets policy
- Never commit passwords, tokens, API keys, private keys, or other secrets.
- Keep sensitive values in untracked local files or environment variables.

## Documentation maintenance
- Internal runbooks: `docs/content/docs/` (Fumadocs). Sidebar order: `docs/content/docs/meta.json`.
- When changing justfile recipes, bootstrap phases, Brewfile groups, or home layout — update the matching MDX page and nested `AGENTS.md` in the same change.
- AI harness docs point to `wyattowalsh/agents`; only env var names belong in dotfiles.
- Validate doc changes with `just docs-ci` before merge.