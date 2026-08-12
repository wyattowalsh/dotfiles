# Brew inventory

`rig/brew/Brewfile` is the **transfer-oriented desired state** for the full-rig Apple Silicon Mac (formulae, casks, selected `mas`, fonts, Quick Look). It is reviewed intent, not an unfiltered dump of disk.

`rig/brew/exclude.txt` lists tokens intentionally skipped from live inventory.

## Commands

```bash
just inventory-redacted   # local/Brewfile.raw, local/mas.raw, local/apps-all.txt (ignored)
just brew-check           # brew bundle check --file rig/brew/Brewfile
just bootstrap --apply --no-upgrade   # first restore on a new Mac
```

## Groups

Comment headers in `Brewfile` classify intent (`# core-cli`, `# dev-languages`, GUI sections, `# mas`, …).

## Promotion checklist

1. Inspect `local/` inventory (never commit it)
2. Promote, exclude, or document as manual
3. Edit `rig/brew/Brewfile`
4. `just brew-check` then bootstrap dry-run

See `rig/brew/AGENTS.md` and `docs/content/docs/packages.mdx`.
