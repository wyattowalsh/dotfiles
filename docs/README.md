# Internal Docs

Fumadocs + Next.js site for operational runbooks, validation commands, and package/AI policy. Content lives in `content/docs/`; the app shell is under `app/`.

## Commands

```bash
just docs-install    # pnpm install in docs/
just docs-check      # typecheck (requires node_modules)
just docs-build      # production build → docs/out
just docs-ci         # frozen lockfile install + typecheck + build (CI parity)
```

Local preview after install:

```bash
cd docs && pnpm dev
```

## Content graph

| Page | Purpose |
| --- | --- |
| `index` | Landing, command surface, in/out of git |
| `fresh-mac` | macOS bootstrap runbook |
| `ssot-workflow` | Inventory → promote → validate |
| `home-config` | Chezmoi + root symlink layout |
| `validation` | justfile check matrix |
| `packages` | Brewfile group reference |
| `ai-mcp` | MCPHub-first policy |

Sidebar order is defined in `content/docs/meta.json`.

## Principles

- Describe **tracked** manifests and verified `just` commands — not private host state
- No tokens, auth files, telemetry, histories, or session databases in pages
- When repo behavior changes, update the matching MDX page in the same PR
- Validate with `just docs-ci` before merging doc-impacting changes