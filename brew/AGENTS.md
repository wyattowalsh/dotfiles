# AGENTS

## Scope

`brew/Brewfile` — curated Homebrew Bundle desired state (formulae, casks, taps, fonts, services).

## Rules

- **Curate, don't dump** — `local/Brewfile.raw` is evidence; promote only after intent classification
- Group entries with comment headers (`# core-cli`, `# dev-languages`, etc.)
- Document `restart_service` intent explicitly; keep stopped DB/cloud services stopped unless promoted
- Never commit raw inventory dumps to `brew/Brewfile`
- Validate with `task brew:check` when Homebrew is available

## Promotion flow

1. `task inventory:redacted` → review `local/Brewfile.raw`
2. Add entry to appropriate Brewfile group
3. `task brew:check`
4. `task bootstrap -- --apply`

## Docs sync

Update `docs/content/docs/packages.mdx` when adding new groups or materially changing policy.