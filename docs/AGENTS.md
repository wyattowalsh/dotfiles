# AGENTS

## Scope

Internal Fumadocs documentation site (`docs/`). Serves runbooks for the macOS full-rig bootstrap, SSOT workflow, validation, packages, and AI/MCP policy.

## Content rules

- Ground pages in tracked manifests (`brew/Brewfile`, `ai/`, `justfile`, `bootstrap/macos.sh`) — not live `~` inventory
- Keep `content/docs/meta.json` sidebar order aligned when adding or renaming pages
- Use MDX frontmatter `title` + `description` on every page
- Prefer tables and command blocks over prose lists for scanability
- Do not publish private host paths, tokens, or auth state

## When to update

| Repo change | Update |
| --- | --- |
| New justfile recipe | `validation.mdx` + root `README.md` |
| Bootstrap behavior | `fresh-mac.mdx` |
| Brewfile group changes | `packages.mdx` |
| Chezmoi/home layout | `home-config.mdx` + `home/README.md` |
| AI/MCP policy | `ai-mcp.mdx` + `ai/README.md` |
| SSOT promotion flow | `ssot-workflow.mdx` + root `AGENTS.md` |

## Validation

```bash
just docs-install
just docs-check      # pnpm typecheck
just docs-build
just docs-ci         # frozen lockfile + build (CI gate)
```

Commit `docs/pnpm-lock.yaml` whenever `docs/package.json` changes.

## App structure

- `app/page.tsx` — marketing-style landing with links into `/docs`
- `app/docs/` — Fumadocs `DocsLayout` + slug routing
- `lib/source.ts` — Fumadocs loader from `content/docs`
- `source.config.ts` — MDX collection definition

## Not in scope

- Generated OpenAPI reference pages (future; not required for current content graph)
- Public deployment or SEO — internal operator docs only