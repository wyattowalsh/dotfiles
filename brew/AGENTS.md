# AGENTS

## Scope

`brew/Brewfile` — curated Homebrew Bundle desired state (formulae, casks, taps, fonts, services).

## Rules

- **Curate, don't dump** — `local/Brewfile.raw` is evidence; promote only after intent classification
- Group entries with comment headers (`# core-cli`, `# dev-languages`, etc.)
- Document `restart_service` intent explicitly; keep stopped DB/cloud services stopped unless promoted
- Never commit raw inventory dumps to `brew/Brewfile`
- Validate with `just brew-check` when Homebrew is available

## Promotion flow

1. `just inventory-redacted` → review `local/Brewfile.raw`
2. Add entry to appropriate Brewfile group
3. `just brew-check`
4. `just bootstrap --apply`

## Docs sync

Update `docs/content/docs/packages.mdx` when adding new groups or materially changing policy.
