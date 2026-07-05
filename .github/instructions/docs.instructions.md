---
applyTo: "docs/**,README.md,**/AGENTS.md,topics/**"
---

@../../AGENTS.md

## Docs focus

- Internal operator runbooks — not marketing copy
- Ground content in tracked manifests and `Taskfile.yml` commands
- MDX pages live in `docs/content/docs/`; sidebar in `meta.json`
- Update nested `AGENTS.md` when subsystem conventions change

## Content graph

`index` → `fresh-mac` → `ssot-workflow` → `home-config` → `validation` → `packages` → `ai-mcp`

## Validate

```bash
task docs:ci
```

Commit `docs/pnpm-lock.yaml` when `docs/package.json` changes.