## Why

KopiaUI login LaunchAgents keep the GUI open so in-app 04:00 policies can fire. The headless replacement must also remain bounded and recover cleanly: the current runner can hang indefinitely, can abort its EXIT trap on an out-of-scope local variable, and does not notify on failures before the snapshot loop.

## What Changes

- Chezmoi-managed `kopia-nightly` runner and `com.wyattowalsh.kopia-nightly` LaunchAgent (`RunAtLoad=false`, calendar 04:00)
- Disable `com.kopia.kopiaui.login` and `KopiaUI` login agents (re-disable after each run)
- Snapshot the existing 04:00 source list only — never `snapshot create --all`, never `$HOME` itself
- Enforce a true twelve-hour wall-clock ceiling around normal runs and a per-attempt ceiling around repository readiness probes
- Replace the mixed EXIT/TERM/INT trap with deterministic signal exits and one idempotent finalizer
- Report exactly one bounded warning or failure notification for catchable terminal outcomes while preserving the primary exit status
- Expand offline checks to pin timeout, locking, progress, maintenance, cleanup, and notification behavior
- Track Homebrew `kopia/test-builds` CLI; keep KopiaUI cask for manual restore
- Operator runbook under `docs/content/docs/backup.mdx`

## Capabilities

### New Capabilities

- `backup`: Headless, bounded Kopia snapshots with deterministic cleanup, notification, and offline assurance contracts.

### Modified Capabilities

None. This repository has no archived baseline `backup` capability; this change remains its source delta.

## Impact

- Chezmoi-managed nightly runner and LaunchAgent
- Offline checks and operator backup documentation
- Homebrew-provided GNU `gtimeout` at runtime

## Non-goals

- Waking a sleeping Mac at 04:00
- Re-adding the unscheduled home tree
- Changing retention, ignore rules, or the rclone remote
- nix-darwin `launchd.user.agents`
- Running a live snapshot, installing the LaunchAgent, or changing repository credentials during implementation

## Validation

- `just check` (includes static and stubbed `checks/kopia-nightly.sh`; no real `kopia`/`launchctl`/notification mutation)
- `just secrets-scan` and `just docs-ci`
- `just bootstrap --dry-run` still completes
- Live: `kopia-nightly install` / `--dry-run` / `doctor` (no snapshot during implement)
