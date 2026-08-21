# freshen Function Instructions

## Scope

Zsh autoloadable `freshen` and tests under `rig/home/dot_zsh/functions/`.

Deployed to `~/.zsh/functions/` via Chezmoi (`rig/home/dot_zsh/functions/`).
Also autoloadable here: `bak`, `tmpd`, `fkill`.

## Development rules

- Preserve `#compdef freshen` and autoloadable single-file UX unless explicitly changing API
- TDD for behavior changes: failing test in `tests/freshen_test.zsh` first, then minimal fix
- Before completion:

```bash
just check-freshen
```

Version SSOT: `rig/home/dot_zsh/functions/freshen.VERSION` (run `./checks/freshen-version.sh` after bumps).

- `FRESHEN_TEST_KEEP_TMP=1` only when debugging test artifacts

## Safety invariants

- `--dry-run` must not mutate Homebrew, mas, caches, or dev-prune targets
- `--clean-only --dry-run` skips upgrade inventory and all mutations
- Noninteractive mutations require `--yes`
- `--progress=plain --no-color` — no ANSI cursor controls, color escapes, bells, or animations
- Dev-prune must never fall back to `rm` and must refuse broad roots
- Interrupts return 130; clean up child processes and temp files
- Nested helpers must be listed in `_freshen_helper_fns` and unfunctioned on EXIT (no interactive-shell leak)
- Instance lock under the log dir; second concurrent freshen fails; stale PID is reclaimed
- Docker prune and gem cleanup are **opt-in** (`--docker-prune` / `--gem-cleanup`), not default cache steps
- `FRESHEN_UPDATE_TIMEOUT_SEC` defaults to 300 (0 = unlimited); upgrade timeout defaults to 0
- Batch upgrade partial failure triggers sequential residual retry by default (`--no-residual-retry` to disable)
- Residual confirm requires exact per-package upgrade markers **or** a successful timed `brew outdated` that omits the package; inventory failure must not promote to confirmed
- Residual messages: `_err` only for command failure/timeout; rc=0 unconfirmed uses `_warn` (“not confirmed (still outdated|outdated inventory failed)”) and does **not** demote unknown→failed
- Shared `_residual_prepare` for formulae and casks: still-outdated → residual retry; unknown+current → promote; failed+current → leave failed (no retry)
- `FRESHEN_RESIDUAL_INVENTORY_TIMEOUT_SEC` bounds residual outdated inventory (default `FRESHEN_UPDATE_TIMEOUT_SEC` / 300); `FRESHEN_RESIDUAL_MAX` caps residual retries
- Bare Xcode/CLT errors associate to the last `==> Upgrading` candidate
- `--print-trust-plan` runs `brew update` (network); never claim non-mutating
- Human-blocking steps (sudo preflight, confirm) must log `WAITING` and surface a waiting phase state
- Log dir resolution: `FRESHEN_STATE_DIR` → `XDG_STATE_HOME` → macOS Library Logs → `~/.local/state`

## Test layout

- Core harness: `tests/freshen_test.zsh`
- Optional parallel case packs: `tests/cases/*.zsh` (sourced after core tests; auto-runs extra `test_*`)
- Hygiene probes must use same-process patterns (`run_freshen_hygiene_probe`), not only subprocess `run_freshen`

## Privacy / publish hygiene

- Never commit raw freshen logs, full live package inventories, absolute home paths (`/Users/…`, `/home/…`), hostnames, or credentials.
- Fixtures under `tests/fixtures/` must be **synthetic** (short, invented package names) or ≤20-line redacted snippets.
- Docs and help examples use placeholders: `$XDG_STATE_HOME/freshen/`, `~/Library/Logs/freshen/`, `<timestamp>.<pid>.log`.
- Runtime may print real paths and package names to the operator TTY/log; **publish** means git/PR/docs/goldens.
- Gate: `./checks/freshen-privacy.sh` (wired into `just check-freshen`).

## Rewrite criteria (backlog only)

Stay a zsh autoload function unless any **two** are true: non-zsh hosts first-class, sustained language fights after hygiene fixes, public packaged distribution, or TUI needs shell cannot meet.
