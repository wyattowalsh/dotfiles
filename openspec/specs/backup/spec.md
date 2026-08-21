# backup Specification

## Purpose

Nightly Kopia snapshots run headless via CLI at 04:00. KopiaUI is not a scheduler.

## Requirements

### Requirement: Headless 04:00 snapshots

The machine SHALL create the existing 04:00 Kopia sources with the CLI and SHALL NOT keep KopiaUI running for scheduling.

#### Scenario: Explicit source list

- **WHEN** the nightly runner executes
- **THEN** it snapshots only the documented HOME-relative 04:00 paths
- **AND** it does not pass `--all` to `kopia snapshot create`
- **AND** it does not snapshot the home directory itself

#### Scenario: Process lifetime

- **WHEN** the nightly job starts
- **THEN** it quits KopiaUI if running, or aborts if quit fails
- **AND** it does not relaunch KopiaUI when finished

### Requirement: No KopiaUI at login

KopiaUI login LaunchAgents SHALL NOT start the app at session load.

#### Scenario: Login agents disabled

- **WHEN** `kopia-nightly install` or a nightly run completes
- **THEN** `com.kopia.kopiaui.login` and `KopiaUI` are bootstrapped-off / disabled

#### Scenario: Nightly agent is calendar-only

- **WHEN** the nightly LaunchAgent is installed
- **THEN** it uses `StartCalendarInterval` at 04:00
- **AND** `RunAtLoad` is false
- **AND** wall-clock cap is enforced in the runner (`KOPIA_NIGHTLY_TIMEOUT_SEC`, default 43200), not launchd `TimeOut`

### Requirement: Secrets stay off git

Tracked backup files SHALL NOT contain repository passwords, rclone tokens, or Drive folder ids.

#### Scenario: Static check

- **WHEN** `checks/kopia-nightly.sh` runs
- **THEN** it fails if the runner or plist embeds `/Users/` paths, `--all`, `KOPIA_PASSWORD`, or a Drive folder id

### Requirement: Dry-run install

Install and snapshot paths SHALL support a non-mutating dry-run.

#### Scenario: Preview

- **WHEN** `kopia-nightly --dry-run` or `kopia-nightly install --dry-run` is invoked
- **THEN** no repository write and no launchctl mutation occurs
