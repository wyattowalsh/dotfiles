## Why

`--storage-plan` is a restore-readiness report that currently lists folder sizes without action class, restore path, or backup-of-record status. `--dev-prune` trashes matching project caches with no recency or live-workspace skip, even though a 14-day skip was already decided. files-buddy holds those policies; they belong in `freshen`'s existing lanes, not as a second product.

## What Changes

- `--dev-prune` skips caches newer than 14 days (mtime) and live-workspace candidates; still `gomi` only
- `--storage-plan` labels surfaces (`cache-prune` / `review` / `report-only`) with restore hints; splits Xcode/AI paths; optional docker `system df` and `nix store gc --dry-run`
- Read-only Kopia/TM status, fail-closed (`verify-unknown`)
- Next Actions may mention `mo clean -n` and files-buddy for offload/dedupe; freshen does not run them
- Version 1.10.0; operator docs + function `AGENTS.md` invariants

## Capabilities

### New Capabilities

- `freshen`: brew/mas orchestrator reclaim sidecar (storage-plan classification, age-gated `--dev-prune`, backup-of-record report)

### Modified Capabilities

None. Backup/Kopia nightly runner is unchanged (status is a read of `kopia repository status` only).

## Impact

- `rig/home/dot_zsh/functions/freshen` (+ tests, VERSION, nested `AGENTS.md`)
- `docs/content/docs/freshen.mdx` (and hub description if it stays in parity)

## Non-goals

- Calling files-buddy `fb.py` or parsing Mole JSON
- Live `mo clean` / `mo purge`
- 30-day default-yes, `--yes` category batches, manifests/undo
- TM thinning, `kopia cache clear`, iCloud evict, docker volume prune
- bun cache `rm` → `gomi`
- Promoting `brew "mole"`
- Adding `target` / `dist` / `build` / whole `.next` as prune names

## Validation

- `just check-freshen`
- `just docs-ci` when `freshen.mdx` / hub copy changes
- `just secrets-scan`
- Live Mac (not CI): `--storage-plan` and `--dry-run --dev-prune` with redacted output
