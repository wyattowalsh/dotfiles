# Change: Portable agent-dev-env bootstrap

## Why

Linux setup installed a hardcoded 14-skill `npx` list and cloned agents to `~/dev/tools/agents`. macOS bootstrap installed none of the harness stack. Operators and coding agents need one preview-first installer that projects wyattowalsh/agents (instructions, hooks, plugins, skills, tools) and can start local MCPHub without becoming a second MCP SSOT.

## What Changes

- Thin `rig/bootstrap/dev-env.sh` locates an agents checkout and execs `scripts/bootstrap-dev-env.sh`
- `just bootstrap-dev` defaults to dry-run
- `linux.sh` delegates the agent stack to that wrapper (no hardcoded skill list)
- `macos.sh` prints the next command; optional `--with-dev-env` / `--require-dev-env`
- Operator docs on the AI page; env **names** only

## Non-goals

- Vendoring MCP JSON or client manifests in this repo
- Starting the MCPHub Cloudflare tunnel
- `npx skills add --skill '*'`
- Writing Cursor `cli-config` / `state.vscdb`
- Auto-applying the agent stack from a default `just bootstrap --apply`

## Validation

- `just check-shell`
- `just bootstrap-dev --dry-run` (requires a local agents checkout with the new script)
- `just check` and `just docs-ci` / `just secrets-scan` when docs change
