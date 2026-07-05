# AGENTS

## Purpose
This repository is a **private, personal, internal-only** dotfiles SSOT for the `w4w-mbp` rig (`/Users/ww`). It captures curated desired state for shell, editor, git, Homebrew, nix-darwin, Chezmoi-managed home config, and AI/MCP bootstrap. Treat the live Mac as inventory (`task inventory:redacted` → `local/`), promote intentional changes into tracked files, and keep secrets out of git.

## SSOT workflow
1. Run `task inventory:redacted` to refresh ignored `local/Brewfile.raw` and config-dir inventory.
2. Diff live vs repo (`cmp` for `.zshrc`/`.p10k.zsh`, `task home:diff`, `task brew:check`).
3. Promote curated changes into `brew/Brewfile`, `home/`, root dotfiles, and `darwin/` as appropriate.
4. Validate with `task check` before `task bootstrap -- --apply` on macOS.

## Files overview
- `setup.sh`: main bootstrap entrypoint (should converge system state when re-run; supports `--dry-run`, `--verbose`, and `--smoke-check`).
- `Taskfile.yml`: canonical workflow runner for bootstrap, checks, docs, Brew, Darwin, AI/MCP, inventory, and secret scans.
- `bootstrap/`: macOS full-rig bootstrap scripts.
- `brew/`: curated Homebrew Bundle desired state and package notes.
- `darwin/`: nix-darwin/Home Manager scaffold for Apple Silicon macOS.
- `home/`: Chezmoi-style home configuration templates.
- `ai/`: sanitized MCPHub-first AI/MCP manifests and generated examples.
- `docs/`: internal Fumadocs documentation site.
- `checks/`: validation and smoke-check scripts used by Taskfile targets.
- `openspec/`: OpenSpec change notes for non-trivial workflow/public structure changes.
- `.zshrc`: Zsh runtime configuration.
- `.p10k.zsh`: Powerlevel10k prompt configuration.
- `.gitconfig`: shared Git configuration defaults.
- `.ripgreprc`: default ripgrep options.
- `.editorconfig`: cross-editor formatting defaults.
- `.copilot/lsp-config.json`: Copilot CLI LSP configuration (symlinked to `~/.copilot/lsp-config.json`).
- `.copilot/mcp-config.json`: Copilot CLI MCP server configuration (symlinked to `~/.copilot/mcp-config.json`).
- `.github/lsp.json`: repository LSP configuration used by GitHub tooling.
- `.github/copilot-instructions.md`: repository instructions used by GitHub Copilot.
- `.claude/CLAUDE.md`: Claude-specific usage guidance.
- `.config/claude/mcp.json`: Claude MCP server configuration.
- `AGENTS.md`: repository conventions for humans and automation.
- `GEMINI.md`: Gemini-specific usage guidance.
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

## AI bootstrap notes
- `setup.sh` installs `@anthropic-ai/claude-code`, `@google/gemini-cli`, `@github/copilot`, and `@openai/codex` via npm when missing, and installs `github/gh-copilot` for `gh` when available.
- `setup.sh` also maintains startup shim links for `claude`, `gemini`, `copilot`, and `codex` in `~/.local/bin` so those commands resolve before `nvm` lazy initialization.
- `setup.sh` installs skills from `wyattowalsh/agents` (no `gh:` prefix) via non-interactive `npx -y skills add --yes` with a dedicated longer timeout (`SKILLS_INSTALL_TIMEOUT_SECONDS=300`) and: `add-badges`, `agent-conventions`, `email-whiz`, `frontend-designer`, `honest-review`, `host-panel`, `javascript-conventions`, `learn`, `mcp-creator`, `orchestrator`, `prompt-engineer`, `python-conventions`, `research`, `skill-creator`.
- Skills target agents are limited to: `claude-code`, `codex`, `gemini-cli`, and `github-copilot` (only if each CLI is installed).
- Universal skills from `~/.agents/skills` are mirrored into `~/.copilot/skills`, `~/.codex/skills`, and `~/.gemini/skills` (for installed CLIs) to improve skill detection.
- Copilot/Codex require provider authentication after install; skills install may warn and continue when blocked by auth/network constraints.
- `setup.sh` installs `wagents` as an optional step: it tries `uv tool install wagents`, falls back to `uv tool install --from "$HOME/dev/tools/agents" wagents`, and warns/continues if still unavailable.
- `setup.sh` skips `chsh` default-shell updates in Codespaces or non-interactive sessions.

## Bash safety conventions
- Start bash scripts with: `set -euo pipefail`.
- Verify required commands before use: `command -v <cmd> >/dev/null 2>&1`.
- Manage symlinks with replacement semantics: `ln -sfn <source> <target>`.
- Quote variable/path expansions.

## Taskfile conventions
- Use `Taskfile.yml` as the command runner; do not add a `justfile` or Makefile.
- Keep Taskfile tasks thin and delegate complex shell logic to scripts under `checks/` or `bootstrap/`.
- Task targets that may mutate state must provide a dry-run or preview path.

## macOS full-rig conventions
- Treat the live Mac as inventory, not as a blob to commit.
- Curate Homebrew packages by intent before promoting them to `brew/Brewfile`.
- Keep nix-darwin/Home Manager host-specific values in `darwin/hosts/`.
- Keep portable home configuration in `home/` and private values in local Chezmoi data or untracked overrides.
- MCPHub is the default AI/MCP control plane; direct MCP configs are fallback/bootstrap only.

## No secrets policy
- Never commit passwords, tokens, API keys, private keys, or other secrets.
- Keep sensitive values in untracked local files or environment variables.

## Documentation maintenance
- Internal runbooks: `docs/content/docs/` (Fumadocs). Sidebar order: `docs/content/docs/meta.json`.
- When changing Taskfile targets, bootstrap phases, Brewfile groups, home layout, or AI/MCP policy — update the matching MDX page and nested `AGENTS.md` in the same change.
- Root `README.md` stays the public-facing overview; `docs/` is the operator deep-dive.
- Validate doc changes with `task docs:ci` before merge.
- `topics/` READMEs are lightweight ownership maps; link to canonical SSOT paths instead of duplicating manifest content.
