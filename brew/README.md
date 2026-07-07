# Brew Inventory

`brew/Brewfile` is **curated desired state** for the full-rig Mac. It is not a mirror of everything installed on disk.

## Commands

```bash
just inventory-redacted   # writes local/Brewfile.raw (ignored)
just brew-check           # brew bundle check --file brew/Brewfile
just bootstrap --apply   # brew bundle install on macOS apply
```

## Groups

Comment headers in `Brewfile` classify intent:

- `# core-cli` — terminal essentials (`ripgrep`, `uv`, `gh`, …)
- `# dev-languages` — runtimes (`node`, `go`, `docker`, …)
- `# ai-tools` — AI/platform CLIs
- `# browsers/productivity/media` — casks
- `# fonts`, `# quicklook` — typography and previews

## Promotion checklist

1. Find package in `local/Brewfile.raw`
2. Decide group and service policy (`restart_service` or not)
3. Add to `brew/Brewfile`
4. `just brew-check`
5. Update `docs/content/docs/packages.mdx` if policy changes

See `brew/AGENTS.md` for agent conventions.
