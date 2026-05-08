# AGENTS

## Scope
AI client, MCPHub, skill, agent, and generated config sources.

## Rules
- MCPHub is the default control plane; direct MCP configs are fallback/bootstrap only.
- Use placeholders for secrets, especially MCP bearer tokens and API keys.
- Do not copy local auth, logs, session DBs, telemetry, or provider state.
- Validate every generated client surface with client-specific schema checks where available.

