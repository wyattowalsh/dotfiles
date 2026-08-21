## Why

The rig already brews most of the CLI suite (`ast-grep`, `just`, `mise`, `shellcheck`, `shfmt`, `duckdb`, `rclone`, `dust`, `duf`, `xh`). Operators still lacked durable config, docs, and gates, plus a few missing formulae (Atuin, harehare `mq`, Bats, VisiData, `s5cmd`, isolated Agent Deck trial). Claude/Codex Atuin hooks cannot live in this repo: wagents home sync is the hook SSOT and previously dropped `PostToolUseFailure`.

## What Changes

- Document and enforce `just` (recipes) vs `mise` (versions) vs direnv (env) vs inventory-only `go-task`; add `just --unstable --fmt --check`; forbid repo-root mise.toml / `[tasks]`
- Brew + zsh + Chezmoi for Atuin (local-only, daemon search, Ctrl-R, no up-arrow/AI, first-run `atuin import zsh`)
- Agents repo: native `PostToolUseFailure`, fail-open `hooks/atuin-agent-hook.sh`, context-mode registry rows, external-hooks registry
- Chezmoi ast-grep global `sgconfig.yml`; Brew harehare `mq`
- CI + `check-shell`: ShellCheck required in CI, `shfmt -d -i 2 -ci -bn`, `bats-core` / `checks/*.bats`
- DuckDB rc + VisiData; document s5cmd vs rclone (Kopia stays rclone); keep `du`/`df`; xh aliases when names are free
- Trial `# trial-agent-deck` with isolated `tmux -L agent-deck`; Ghostty remains the daily multiplexer; no conductor
- Linux apt: `shellcheck` / `shfmt` / `bats` only — no Atuin/mq/Agent Deck github-binary sprawl

## Capabilities

### New Capabilities

- `cli-suite`: Curated CLI install, XDG/zsh config, and CI gates for shell history, search, data, HTTP, and an isolated Agent Deck trial.

### Modified Capabilities

None. This repository has no archived baseline `cli-suite` capability; this change remains its source delta.

## Impact

- Brewfile groups, zshrc/aliases, Chezmoi home files, just/CI, docs MDX, nested AGENTS
- wyattowalsh/agents hook registry + merge allowlists (required for Atuin hooks to survive home sync)

## Non-goals

- Atuin Cloud / `atuin login`
- OpenCode/pi Atuin hooks
- Restoring tmux as a daily multiplexer or TPM
- Replacing Kopia's rclone backend
- Vendoring MCP/harness JSON into this repo
- Rewriting existing alias expansions (`du`/`df`/agent aliases)

## Validation

- `just check` (includes `check-just-fmt`, `check-mise-boundary`, `check-bats`, ShellCheck/shfmt)
- `just docs-ci` and `just secrets-scan`
- `just brew-check`
- Live Mac: brew bundle new formulae, Chezmoi apply, Atuin import if empty, `just bootstrap-dev --apply` for hooks
