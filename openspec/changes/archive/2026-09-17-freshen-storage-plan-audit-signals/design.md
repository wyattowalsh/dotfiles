# Design: freshen-storage-plan-audit-signals

## Constraints

- Report-only. Prints labels, optional sizes, skip reasons, native command names. Does not prune, delete, empty trash, offload, or exec Mole/files-buddy.
- Chezmoi source: `rig/home/dot_zsh/functions/freshen`.
- Reuse `_run_report_cmd` / `_timeout_sec_env`. Per-probe timeouts so one hang cannot stall the report.

## Catalog consumer (`_print_storage_plan`)

Existing loop `du`s every existing catalog path when `FRESHEN_STORAGE_SCAN_SURFACES=1`. Change it to:

- Keep printing class + path + restore hint.
- Never pass these to `_du_kb`: `${HOME}/.cache`, `${HOME}/Library/Caches`, `${HOME}/Library/Developer/CoreSimulator`, `${HOME}/Library/CloudStorage`, `/Library/Developer/CoreSimulator`.
- Leaf caches that exist MAY be sized (uv, `_npx`, pnpm v11 store, OpenCode, huggingface).
- New leaves that are missing print `absent` (non-fatal). Existing rows still skip if missing.
- In-use probe only for uv / `_npx` / pnpm v11 store / OpenCode.

Mole is already text-only in Next Actions (`mo clean -n (not invoked by freshen)`). Keep that. Footer restates `mo` is not invoked.

## In-use

`_storage_path_in_use` uses `ps -axo pid=,command=` with a 2s timeout. Match the absolute path prefix only. `ps` failure/timeout → in-use (fail-closed). Display `in-use / skip`. Never recommend `--force`. Tests stub `ps` on `TEST_BIN`.

## Kopia

Keep timed `kopia repository status` (no password, stdin closed). Then:

- Override `FRESHEN_KOPIA_NIGHTLY_RUNNING=1|0` for tests/operators.
- Else Darwin `launchctl print gui/$UID/com.wyattowalsh.kopia-nightly`.
- If running: `nightly running; coverage not probed`; unique-cold not recommended.
- Else `kopia snapshot list --all --json` stdout only; parse with python3; stderr discarded.
- Expected sources: Documents, Movies, Music, Pictures, Public, `dev`, `src` under `$HOME`. Always print `Downloads not covered`.
- Unique-cold warning omitted only if reachable AND each expected source has latest `fileCount>0` and `totalSize>0`.

Existing test `test_storage_plan_kopia_reachable_omits_unique_cold_block` must flip: reachable stub with empty list keeps unique-cold closed.

## simctl

Skip when `FRESHEN_UNDER_TEST` is set unless `FRESHEN_TEST_SIMCTL=1` (avoid real xcrun in `just check-freshen`). Otherwise `xcrun simctl runtime list`; never `runtime delete`; license error is non-fatal.

## Out of scope

`--cache-prune` mutate flag; simulator delete; Drive offload; `gomi` empty; `mo clean`.
