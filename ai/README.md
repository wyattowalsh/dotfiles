# AI and MCP Configuration

Source-of-truth manifests for MCPHub and generated AI client configuration.

## Layout

```
ai/
├── mcphub.manifest.json     # MCPHub transport, endpoints, fallbacks
├── client-surfaces.json     # Per-client generation targets
├── templates/               # Config templates with placeholders
├── generated/*.example.json # Sanitized examples
└── schemas/                 # JSON Schema for validation
```

## Policy

| Layer | Role |
| --- | --- |
| MCPHub | Default control plane (`MCPHUB_BEARER_TOKEN` via env) |
| Direct MCP JSON | Bootstrap/recovery in `.copilot/`, `.config/claude/` |
| `setup.sh` (Linux) | Installs CLIs, skills, shim links |

Never commit literal tokens, OAuth files, logs, histories, or session databases.

## Known migration debt

Before promoting local Gemini/OpenCode MCP config into tracked files:

- Replace literal MCPHub bearer tokens with `${MCPHUB_BEARER_TOKEN}`
- Validate Gemini `mcpServers` shape against current CLI schema
- Review OpenCode default model separately from MCP migration

## Validate

```bash
just ai-check
just secrets-scan
```

Operator docs: `docs/content/docs/ai-mcp.mdx`