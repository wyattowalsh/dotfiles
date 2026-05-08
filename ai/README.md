# AI and MCP Configuration

This directory contains the source-of-truth manifests for generated AI client configuration.

## Policy
- MCPHub is the default control plane.
- Direct MCP server configs remain as bootstrap and recovery fallbacks.
- Literal tokens, API keys, OAuth files, auth databases, logs, histories, and session state are never committed.
- Client-specific generated files must validate before they are installed.

## Current Local Issues To Resolve
- Gemini rejects the current local `mcpServers.mcphub_all` shape.
- The local Gemini file contains a literal MCPHub bearer token and must be converted to `${MCPHUB_BEARER_TOKEN}` before any tracked import.
- OpenCode currently defaults to `openai/gpt-5.5`; model stability should be reviewed separately from MCP migration.

Validate with:

```bash
task ai:check
```

