---
applyTo: "docs/**,README.md,**/AGENTS.md"
---

@../../AGENTS.md

## Docs focus

- Operator runbooks for this personal public SSOT — not marketing copy
- Ground content in tracked manifests and `justfile` commands
- MDX pages live in `docs/content/docs/`; sidebar in `meta.json`
- Update nested `AGENTS.md` when subsystem conventions change
- Env names only; never secrets, `/Users/<name>/` paths, or `local/` dumps

## Content graph

See `docs/content/docs/meta.json`. Primary paths: `index`, `fresh-mac`, `linux-setup`, `ssot-workflow`, `home-config`, `shell`, `freshen`, `validation`, `packages`, `ai-harness`, `security`, `docs-maintenance`.

## Validate

```bash
just docs-ci
just secrets-scan
```

Commit `docs/pnpm-lock.yaml` when `docs/package.json` changes.
