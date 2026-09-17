## Context

`freshen` stays a zsh autoload function. files-buddy remains the agents-repo reclaim CLI. This change steals policy for two existing flags.

## Goals / Non-Goals

**Goals**

- 14-day mtime skip on `--dev-prune` (`FRESHEN_DEV_PRUNE_MIN_AGE_DAYS`, `0` disables)
- Live-workspace skip that does not disable `--dev-prune-root=$HOME/dev` when cwd is that root
- Classified `--storage-plan` rows without extra mutation
- Fail-closed backup status; no Kopia password on argv
- Companion Next Actions as text only

**Non-goals**

See proposal. No Python helper, no Mole parser.

## Decisions

1. **Age uses mtime only.** No git last-activity in v1.
2. **Live workspace.** Skip when cwd equals the candidate, cwd is under the candidate, or the candidate is under cwd *unless* cwd equals the prune root (so an explicit `$HOME/dev` root still scans siblings).
3. **Sizing stays opt-in** via `FRESHEN_STORAGE_SCAN_SURFACES=1`. Labels print without `du`.
4. **Drop the single `~/Library/Developer` blob** in favor of Xcode children to avoid double-count.
5. **Docker/nix probes are report-only.** `docker info` + `docker system df`; `nix store gc --dry-run` only. Never prune/gc mutate from `-S`.
6. **Kopia:** timed `kopia repository status` with no `-p`/`--password`, stdin closed. Timeout knob `FRESHEN_BACKUP_STATUS_TIMEOUT_SEC` (default 20; `0` unlimited). Missing or non-zero → `verify-unknown` or `not installed`. `-S` still exits 0.
7. **Mole:** if `mo` is on PATH, print `mo clean -n` in Next Actions; do not invoke `mo`.
8. **Helpers** are nested, listed in `_freshen_helper_fns`, unfunctioned on EXIT.
9. **Find** walks `_dev_prune_validated_root` (`:A`) with `-P`. Target checks use the frozen root string.
10. **`~/.docker` parent is not a catalog row**; volumes stay report-only; images via `docker system df`.

## Risks / Trade-offs

- Existing `--dev-prune` tests mkdir a fresh `node_modules`; they must stamp mtime old or set `MIN_AGE_DAYS=0`.
- Real `tmutil` may run in tests on Darwin (`PATH` includes `/usr/bin`). Keep it read-only and non-fatal.
- Classified rows grow help/output; keep `--progress=plain` free of cursor controls.

## Migration

None. Safer prune default (fewer deletions). Operators who want old behavior set `FRESHEN_DEV_PRUNE_MIN_AGE_DAYS=0`.
