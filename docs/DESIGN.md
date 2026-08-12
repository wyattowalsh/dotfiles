# DESIGN — Dotfiles operator docs

Design system for the Fumadocs site under `docs/`. Implementation: `app/global.css` (Tailwind CSS v4 + Fumadocs **shadcn** preset + PostCSS).

**Palette:** Signal Graphite — cool paper / ink navy + teal signal.  
**Icons:** [Phosphor Icons](https://github.com/phosphor-icons/react) (MIT), **duotone** weight for hub/nav marks — not Lucide.  
**Brand:** lowercase `dotfiles` wordmark (JetBrains Mono + gradient shift + signal pulse).  
**Chrome:** GitHub via `githubUrl`, Runbooks / Start / Validate nav.  
**Layers:** fixed grid + glow under content; glass cards.  
**Diagrams:** Mermaid `theme: base` + CSS vars in `lib/mermaid-theme.ts` (synced to palette).

## Intent

Operator-first documentation: **calm, dense, scannable**. Prefer clarity over decoration. Personal public SSOT for bootstrap and day-to-day rig maintenance—not marketing.

## Principles (priority order)

When principles conflict, higher wins.

### 1. Scan over scroll

Operators land to find a command or path. Lead with titles, one-line descriptions, and monospaced first commands.

- **Test:** “What command next?” answerable within one screenful on the landing page.
- **Counter-example:** Long prose before the first actionable command.

### 2. Structure before style

Correct hierarchy (nav, cards, TOC) beats novel chrome.

- **Application:** Prefer Fumadocs layouts over custom shells.
- **Counter-example:** Hand-rolled sidebars that diverge from DocsLayout.

### 3. Calm density

Tight spacing; no hero theater. Cards and tables carry weight.

- **Application:** Landing uses group labels + card grids; runbooks use short sections.
- **Trade-off:** Accepts less “wow” for faster operator throughput.

### 4. Token fidelity

Use Fumadocs/shadcn semantic colors (`fd-*` / theme vars). Do not invent one-off hex in components.

- **Application:** `bg-fd-card`, `text-fd-muted-foreground`, `border-fd-border`.
- **Counter-example:** `#1a1a1a` inline styles on cards.

### 5. Motion as feedback only

≈150ms transitions on border/shadow/opacity; honor `prefers-reduced-motion`.

- **Application:** `motion-reduce:transition-none` on interactive cards; global reduced-motion kill-switch in CSS.

### 6. Accessible by default

Visible focus rings, ≥44px primary hit targets, contrast AA+.

- **Application:** Primary CTA `min-h-11`; focus-visible rings on cards and buttons.

## Color — Signal Graphite

Semantic roles (Fumadocs shadcn slots, **custom values**):

| Role | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#f3f6f8` | `#0b1220` | Page canvas |
| `foreground` | `#0b1220` | `#e8eef4` | Body text |
| `primary` | `#0f766e` teal | `#2dd4bf` | CTA, signal, icons |
| `accent` | `#ccfbf1` | `#164e63` | Soft wash / Mermaid nodes |
| `card` | `#fafcfd` | `#121a2b` | Cards, mermaid host |
| `border` / `muted` | cool slate | deep navy | Structure |

Light/dark via `next-themes` (RootProvider) and `.dark` on `<html>`.

## Icons — Phosphor (OSS)

| Rule | Detail |
| --- | --- |
| Package | `@phosphor-icons/react` (MIT) |
| Weight | **duotone** on hub/group/nav marks; regular/bold sparingly |
| Density | One icon per hub card + group label + nav brand — **not** every MDX heading |
| Map | `lib/icons.tsx` keyed by hub slug / group |

## Mermaid — global theme

| Rule | Detail |
| --- | --- |
| Engine | `theme: "base"` + `themeVariables` from CSS vars |
| Host | `.mermaid-host` card chrome in `global.css` |
| Content | Multi-branch flows only; optional `classDef signal/mute` matching palette |
| SSOT | `lib/mermaid-theme.ts` + `components/mdx/mermaid.tsx` |

## Typography

| Role | Treatment |
| --- | --- |
| UI / body | System sans (`--font-sans`) |
| Commands / paths | System mono (`--font-mono`) |
| H1 | `text-3xl`–`text-4xl`, tight tracking, bold |
| Section labels | `text-sm`, uppercase, muted, wide tracking |
| Card title | `text-base` semibold |
| Card body | `text-sm` muted |

## Layout

- Max content width: `--fd-layout-width: 1400px`.
- Landing: `max-w-5xl` column; responsive **1 → 2 → 3** card grid.
- Docs: Fumadocs DocsLayout (sidebar + TOC).

## Components

Prefer Fumadocs UI: `HomeLayout`, DocsLayout, Cards, Callouts, Tabs, Steps, Accordions, Mermaid MDX.

Landing cards: `rounded-xl border bg-fd-card`; hover border toward primary; focus-visible ring.

Primary CTA: solid `bg-fd-primary`, min height 44px.

## Content density

| Surface | Density |
| --- | --- |
| Landing hub | High — groups + cards + first command |
| Runbooks | Medium — short sections, copy-paste commands |
| Reference | High — tables, path maps |

## Implementation map

| Concern | File |
| --- | --- |
| CSS entry + tokens | `app/global.css` |
| PostCSS / Tailwind | `postcss.config.mjs`, `package.json` |
| Icons | `lib/icons.tsx` (Phosphor duotone) |
| Mermaid theme | `lib/mermaid-theme.ts`, `components/mdx/mermaid.tsx` |
| Root shell + theme | `app/layout.tsx`, `components/provider.tsx` |
| Landing | `app/page.tsx`, `lib/sections.ts`, `lib/hub-manifest.json` |
| Docs chrome | `app/docs/layout.tsx` |
| MDX components | `components/mdx.tsx` |
| This document | `DESIGN.md` |

## Anti-patterns

- Importing `fumadocs-ui/css/*.css` **without** Tailwind v4 (ships uncompiled `@theme` / `@apply` → unstyled site).
- One-off hex colors in TSX.
- Disabling theme toggle or system preference.
- Marketing layout patterns on operator pages.
