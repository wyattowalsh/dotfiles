# AGENTS

## Scope

Internal Fumadocs documentation site (`docs/`). Serves operator runbooks for macOS bootstrap, SSOT workflow, validation, packages, shell, and AI harness pointers.

## Content rules

- Ground pages in tracked manifests (`rig/brew/Brewfile`, `justfile`, `rig/bootstrap/macos.sh`) — not live `~` inventory
- Keep `content/docs/meta.json` sidebar order aligned when adding or renaming pages, and update `lib/hub-manifest.json` for the same slug set (`just docs-hub-parity`)
- Use MDX frontmatter `title` + `description` on every page
- Prefer tables and command blocks over prose lists for scanability
- Env vars: **names only**. Never commit secrets, absolute `/Users/<name>/` paths, or `local/` dumps
- Prefer generic host wording in prose; flake target only inside copyable commands when required

## When to update

| Repo change | Update |
| --- | --- |
| New justfile recipe | `validation.mdx` |
| Bootstrap behavior | `fresh-mac.mdx` |
| Brewfile group changes | `packages.mdx` |
| Chezmoi/home layout | `home-config.mdx` |
| Shell structure / tools | `shell.mdx` |
| freshen operator modes | `freshen.mdx` |
| AI harness pointer | `ai-harness.mdx` (SSOT: wyattowalsh/agents) |
| SSOT promotion flow | `ssot-workflow.mdx` |
| Docs workflow itself | `docs-maintenance.mdx` |
| Sidebar / hub cards | `meta.json` **and** `lib/hub-manifest.json` |

## Validation

```bash
just docs-install
just docs-check
just docs-build
just docs-ci
just secrets-scan
```

Commit `docs/pnpm-lock.yaml` whenever `docs/package.json` changes.

## App structure

- `app/page.tsx` — landing from `lib/sections.ts`
- `app/docs/` — Fumadocs DocsLayout + slug routing
- `components/mdx.tsx` — Callout, Mermaid, Steps, Tabs, Cards
- `app/api/search` — static Orama index
- `lib/source.ts` — loader from `content/docs`

## Not in scope

- Generated OpenAPI reference pages
- Public deployment or SEO marketing
