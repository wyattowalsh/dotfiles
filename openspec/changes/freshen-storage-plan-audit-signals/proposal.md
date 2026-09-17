# Change: freshen-storage-plan-audit-signals

## Why

`freshen --storage-plan` is already report-only and does not invoke `mo` or files-buddy. A live cleanup pass showed the catalog is too coarse: high-yield caches were hidden inside parent `~/.cache`; unique-cold dropped once `kopia repository status` succeeded even with incomplete snapshots; File Provider roots must not be `du`'d.

## What Changes

- Keep `--storage-plan` report-only. No mutate flag. No `mo` / Mole / files-buddy / `gomi` / `simctl runtime delete` / `kopia snapshot verify`.
- Named leaf rows: uv, npm npx, pnpm v11 store, OpenCode cache, system CoreSimulator, CloudStorage.
- Parent cache rows unsized. CloudStorage and `/Library/Developer/CoreSimulator` never `du`'d.
- In-use skip via `ps -axo pid=,command=` matching the absolute prefix (never `pgrep -afil`, never `--force`).
- Kopia per-source coverage; Downloads uncovered; unique-cold stays closed unless every expected source has a non-zero snapshot; skip coverage if the nightly LaunchAgent is running.
- simctl unused runtimes report-only; Xcode license skip is non-fatal.
- Footer: claimed ≠ measured ≠ staged; Mole named, not invoked.

## Capabilities

- `freshen`: additive `--storage-plan` audit signals; existing SHALL NOTs remain.

## Impact

- `rig/home/dot_zsh/functions/freshen`
- `rig/home/dot_zsh/functions/tests/cases/storage_reclaim_policy.zsh`
- `docs/content/docs/freshen.mdx`
