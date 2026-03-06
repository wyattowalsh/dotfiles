# AGENTS

## Purpose
This repository is for dotfiles/bootstrap automation so environment setup is repeatable and safe to re-run.

## Files overview
- `setup.sh`: main bootstrap entrypoint (should converge system state when re-run; supports `--dry-run`, `--verbose`, and `--smoke-check`).
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

## No secrets policy
- Never commit passwords, tokens, API keys, private keys, or other secrets.
- Keep sensitive values in untracked local files or environment variables.
