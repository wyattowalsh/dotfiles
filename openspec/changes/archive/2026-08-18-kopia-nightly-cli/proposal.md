# Change: Kopia nightly CLI

## Why

KopiaUI login LaunchAgents keep the GUI open so in-app 04:00 policies can fire. That opens Kopia at launch and leaves it running. Policy schedules do not run without the UI/server. Replace always-on KopiaUI with a headless CLI oneshot at 04:00.

## What Changes

- Chezmoi-managed `kopia-nightly` runner and `com.wyattowalsh.kopia-nightly` LaunchAgent (`RunAtLoad=false`, calendar 04:00)
- Disable `com.kopia.kopiaui.login` and `KopiaUI` login agents (re-disable after each run)
- Snapshot the existing 04:00 source list only — never `snapshot create --all`, never `$HOME` itself
- Track Homebrew `kopia/test-builds` CLI; keep KopiaUI cask for manual restore
- Operator runbook under `docs/content/docs/backup.mdx`

## Non-goals

- Waking a sleeping Mac at 04:00
- Re-adding the unscheduled home tree
- Changing retention, ignore rules, or the rclone remote
- nix-darwin `launchd.user.agents`

## Validation

- `just check` (includes static `checks/kopia-nightly.sh`; no live `kopia`/`launchctl`)
- `just secrets-scan` and `just docs-ci`
- `just bootstrap --dry-run` still completes
- Live: `kopia-nightly install` / `--dry-run` / `doctor` (no snapshot during implement)
