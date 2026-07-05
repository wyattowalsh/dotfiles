# AGENTS

## Scope

`ai/` — MCPHub manifests, client surface definitions, templates, and generated example configs.

## Policy

| Priority | Surface |
| --- | --- |
| 1 | MCPHub groups + `${MCPHUB_BEARER_TOKEN}` |
| 2 | Direct MCP JSON in `.copilot/`, `.config/claude/` (bootstrap/recovery) |
| 3 | Per-client generated files from `ai/templates/` |

## Rules

- Placeholders for all secrets (`${VAR}` syntax)
- Do not copy local auth DBs, logs, session stores, or telemetry into tracked files
- Validate with `just ai-check` before promoting config changes
- Run `just secrets-scan` when touching MCP JSON

## Validate

```bash
just ai-check
just secrets-scan
```

## Docs sync

Update `docs/content/docs/ai-mcp.mdx` and `ai/README.md` when policy or manifest shape changes.