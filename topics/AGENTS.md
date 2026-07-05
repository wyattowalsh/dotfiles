# AGENTS

## Scope

`topics/` — topic-oriented module scaffolding (shell, git, terminal, editors, macOS, packages, AI, MCP, docs, security).

## Status

Scaffolding for future topic-owned install notes and validation. Canonical SSOT today lives in:

- `brew/`, `darwin/`, `home/`, `ai/`, `docs/`, root dotfiles

## Rules

- Keep topics cohesive — one domain per directory
- Link to canonical manifests; do not duplicate Brewfile or MCPHub content inline
- Each topic README should document ownership, validation, and override policy
- Portable config + local override hooks over hardcoded machine state

## When promoting a topic

1. Move install/apply logic from bootstrap into topic module
2. Add justfile recipe or bootstrap hook
3. Document in matching `topics/<name>/README.md` and Fumadocs if operator-facing