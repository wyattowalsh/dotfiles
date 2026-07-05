@./AGENTS.md

## Repo context

- **Private SSOT** for host `w4w-mbp` (`/Users/ww`) — not a public template
- **macOS path:** `task bootstrap` → Brewfile + root symlinks + Chezmoi + nix-darwin
- **Linux path:** `./setup.sh` — apt bootstrap + AI CLI/skills install
- **Inventory:** `task inventory:redacted` → ignored `local/`; promote curated changes only

## Validation before merge

```bash
task check
task ci
```

## AI/MCP

- MCPHub-first; tracked direct MCP JSON is bootstrap fallback only
- Never commit tokens — use `${ENV_VAR}` placeholders
- Run `task ai:check` and `task secrets:scan` when touching MCP config

## Docs

- Fumadocs runbooks in `docs/content/docs/`
- Update matching MDX when changing Taskfile, bootstrap, or manifest policy
- Validate with `task docs:ci`