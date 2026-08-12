# Dotfiles operator docs

Fumadocs + Next.js (static export) for operator runbooks.

- Content: `content/docs/`
- App shell: `app/`
- Design SSOT: [`DESIGN.md`](./DESIGN.md)
- Theme: Tailwind CSS v4 + Fumadocs **shadcn** preset (`app/global.css` + `postcss.config.mjs`)
- Icons: [Phosphor](https://github.com/phosphor-icons/react) (MIT), duotone — `lib/icons.tsx`
- Diagrams: Mermaid global theme — `lib/mermaid-theme.ts`

## Commands

```bash
just docs-install
just docs-check
just docs-build
just docs-ci          # includes docs-css-health (compiled Tailwind)
```

Local preview: `cd docs && pnpm dev`.

## CSS pipeline (do not regress)

Fumadocs UI CSS **must** go through Tailwind v4:

```css
/* app/global.css */
@import "tailwindcss";
@import "fumadocs-ui/css/shadcn.css";
@import "fumadocs-ui/css/preset.css";
```

Never import `fumadocs-ui/css/*.css` from TSX alone — that ships uncompiled `@theme`/`@apply` and unstyles the site.

Operator content SSOT is this tree — not nested subsystem README files. See [docs-maintenance](./content/docs/docs-maintenance.mdx).
