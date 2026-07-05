---
applyTo: "ai/**,.copilot/**,.claude/**,.config/claude/**,GEMINI.md"
---

@../../AGENTS.md

## AI/MCP focus

- MCPHub manifests in `ai/` are SSOT; direct JSON is fallback/recovery
- Replace literal bearer tokens with `${MCPHUB_BEARER_TOKEN}` and similar placeholders
- Never commit provider auth files, logs, histories, or session DBs

## Validate

```bash
task ai:check
task secrets:scan
```

Sync `docs/content/docs/ai-mcp.mdx` when policy or manifest shape changes.