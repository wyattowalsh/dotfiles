# AGENTS

## Scope

Fumadocs documentation site (`docs/`). Serves operator runbooks for macOS bootstrap, SSOT workflow, validation, packages, shell, and AI harness pointers.

**Design SSOT:** `DESIGN.md`. Theme: Tailwind v4 + Fumadocs shadcn preset via `app/global.css` (never import fumadocs CSS without Tailwind). Landing is a path-chip strip + grouped **page-list** (not a card grid) — do not contradict `DESIGN.md`.

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
| Bootstrap behavior | `fresh-mac.mdx` / `linux-setup.mdx` |
| Brewfile group changes | `packages.mdx` |
| Chezmoi/home layout | `home-config.mdx` |
| Shell structure / tools | `shell.mdx` |
| freshen operator modes | `freshen.mdx` |
| AI harness pointer | `ai-harness.mdx` (SSOT: wyattowalsh/agents) |
| SSOT promotion flow | `ssot-workflow.mdx` |
| Docs workflow itself | `docs-maintenance.mdx` |
| Sidebar / landing page-list | `meta.json` **and** `lib/hub-manifest.json` |
| Visual / theme tokens | `DESIGN.md` + `app/global.css` |

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

- `app/global.css` — Tailwind v4 + shadcn/preset CSS entry
- `postcss.config.mjs` — `@tailwindcss/postcss`
- `app/page.tsx` — landing from `lib/sections.ts` (page-list, not cards)
- `app/docs/` — Fumadocs DocsLayout + slug routing
- `components/mdx.tsx` — Callout, Mermaid, Steps, Tabs, Cards (MDX; not the landing)
- `app/api/search` — static Orama index
- `app/llms.txt/route.ts` — Fumadocs `llms` index
- `app/llms-full.txt/route.ts` — concatenated page text
- `lib/source.ts` — loader from `content/docs`
- `DESIGN.md` — design principles + tokens

Operator prose lives under `docs/content/docs/` only.

## Not in scope

- Generated OpenAPI reference pages
- Marketing SEO / brand site (this is operator docs)
