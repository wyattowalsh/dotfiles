# AGENTS

## Scope

`rig/brew/Brewfile` — transfer-oriented Homebrew Bundle desired state (formulae, casks, taps, fonts, Quick Look, selected `mas`).

`rig/brew/exclude.txt` — tokens intentionally not promoted from live inventory.

## Rules

- **Inventory is private** — `just inventory-redacted` writes gitignored `local/` only; never commit dumps
- **Promote with intent** — full-transfer is allowed for this personal rig, but still skip junk (see exclude)
- Group entries with comment headers; **no duplicate** brew/cask basenames (last path segment after `/`). Taps may share a name with a formula. mas vs cask overlap (e.g. WhatsApp) is allowed when dual-channel is intentional
- Docker primary is `cask "docker-desktop"`; do not re-add formula `docker` (excluded)
- Only declare taps required by promoted packages. The sole test-build tap exception is `kopia/test-builds` (required for the kopia nightly CLI). Do not add other test-build taps
- Document `restart_service` explicitly; keep DBs/cloud daemons stopped unless intentional
- Do **not** mass-commit `vscode` extension lines (local inventory only)
- Validate with `just brew-check` (includes `checks/brew-exclude-check.sh`)
- No secrets, emails, host slugs, or absolute home paths in tracked Brewfile comments

## Promotion flow

1. `just inventory-redacted` → review `local/Brewfile.raw`, `local/mas.raw`, `local/apps-all.txt`
2. Classify promote / exclude / manual
3. Edit `rig/brew/Brewfile` (and `rig/brew/exclude.txt` if needed)
4. `just brew-check`
5. `just bootstrap --dry-run` then `--apply` (prefer `--no-upgrade` on a fresh Mac)

## Docs sync

Update `docs/content/docs/packages.mdx` when groups or transfer policy change.
