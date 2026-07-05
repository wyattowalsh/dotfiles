# Packages Topic

Owns package intent, curation policy, and promotion from live inventory.

## Canonical SSOT

- `brew/Brewfile` — Homebrew Bundle desired state
- `darwin/` — nix-managed system/user packages

## Workflow

```bash
just inventory-redacted   # local/Brewfile.raw
# review and classify
just brew-check
just bootstrap --apply
```

See [Package catalog](../../docs/content/docs/packages.mdx) for Brewfile groups.