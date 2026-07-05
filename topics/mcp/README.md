# MCP Topic

Owns MCPHub control plane and direct MCP fallback strategy.

## Policy

1. **MCPHub** — default; groups in `ai/mcphub.manifest.json`
2. **Direct JSON** — `.copilot/mcp-config.json`, `.config/claude/mcp.json` for bootstrap/recovery
3. **Env placeholders** — `${MCPHUB_BEARER_TOKEN}`, API keys never in git

## Validation

```bash
just ai-check
just secrets-scan
```

See [AI and MCP matrix](../../docs/content/docs/ai-mcp.mdx).