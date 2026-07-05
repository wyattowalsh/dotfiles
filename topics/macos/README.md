# macOS Topic

Owns macOS system defaults, launch/service policy, and Apple Silicon host behavior.

## Canonical paths

- `darwin/` — nix-darwin flake and `w4w-mbp` host module
- `bootstrap/macos.sh` — first-run orchestration

## Bootstrap

```bash
task bootstrap -- --dry-run
task bootstrap -- --apply
```

Requires `darwin/flake.lock` on apply. See [Fresh Mac runbook](../../docs/content/docs/fresh-mac.mdx).

## Validation

```bash
task darwin:check
```