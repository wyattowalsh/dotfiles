# Tasks: freshen-storage-plan-audit-signals

## Catalog

- [x] 1.1 Emit named leaves: `~/.cache/uv`, `~/.npm/_npx`, pnpm v11 store, OpenCode cache, system CoreSimulator, CloudStorage
- [x] 1.2 Print `absent` for missing named leaves
- [x] 1.3 Never `du` parent `.cache`, `Library/Caches`, user CoreSimulator, CloudStorage, or `/Library/Developer/CoreSimulator`
- [x] 1.4 OpenCode restore hint forbids uninstall

## In-use / probes

- [x] 2.1 Detect in-use cache leaves via `ps -axo pid=,command=` (fail-closed; no `pgrep -afil`)
- [x] 2.2 Skip `du` and never `--force` for in-use leaves
- [x] 2.3 `simctl runtime list` is report-only; license errors skip without sudo
- [x] 2.4 Never execute `mo`

## Backup coverage

- [x] 3.1 Probe `kopia snapshot list --all --json` unless `com.wyattowalsh.kopia-nightly` is running
- [x] 3.2 Expected sources: Documents, Movies, Music, Pictures, Public, `dev`, `src`, plus nightly dotfiles
- [x] 3.3 Downloads is never covered
- [x] 3.4 Unique-cold stays closed until every expected source has non-zero `fileCount` and `totalSize`; unique models stay report-only
- [x] 3.5 Footer: claimed ≠ measured; staged trash is not confirmed reclaim

## Tests / docs

- [x] 4.1 Case pack `tests/cases/storage_plan_audit_signals.zsh`
- [x] 4.2 Operator docs, domain map, validation gate, AGENTS.md
- [x] 4.3 `just check-freshen` (passed)
