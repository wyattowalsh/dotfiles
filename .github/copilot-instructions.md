@./AGENTS.md

## Repo context

- **Private SSOT** for host `w4w-mbp` (`/Users/ww`) — not a public template
- **macOS path:** `just bootstrap` → Brewfile + root symlinks + Chezmoi + nix-darwin
- **Linux path:** `./setup.sh` — apt bootstrap + AI CLI/skills install
- **Inventory:** `just inventory-redacted` → ignored `local/`; promote curated changes only

## Validation before merge

```bash
just check
just ci
```

## AI/MCP

- MCPHub-first; tracked direct MCP JSON is bootstrap fallback only
- Never commit tokens — use `${ENV_VAR}` placeholders
- Run `just ai-check` and `just secrets-scan` when touching MCP config

## Docs

- Fumadocs runbooks in `docs/content/docs/`
- Update matching MDX when changing justfile recipes, bootstrap, or manifest policy
- Validate with `just docs-ci`