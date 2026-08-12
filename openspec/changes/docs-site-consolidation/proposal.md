# Docs site consolidation

## Why

Operator documentation was split across Fumadocs MDX, `topics/**` scaffolding, and subsystem READMEs. The docs app lacked search, Mermaid rendering, and current Fumadocs patterns.

## What Changes

- Upgrade `docs/` Fumadocs stack (search, Mermaid, MDX components, llms exports, design shell)
- Fold unique operator content from `topics/**` into `docs/content/docs/`
- Delete parallel operator trees (`topics/`) and vendor root stubs (`GEMINI.md`)
- Delete fat operator-facing `home/README.md`; allow **thin** subsystem READMEs (e.g. `rig/brew/README.md`) that only point at manifests + docs
- Slim root `README.md` to entrypoint + pointer into docs
- Keep nested `AGENTS.md` as agent-runtime contracts only

## Impact

- Public repo structure: `topics/` removed; docs content graph expanded
- Humans use `docs/` only for runbooks
- Nested `AGENTS.md` remain agent contracts, not operator prose

## Validation

- `just docs-ci` (frozen install, typecheck, production build, docs-sensitive, docs-hub-parity)
- Hub SSOT: `docs/lib/hub-manifest.json` drives landing + index hub; `meta.json` owns sidebar order
