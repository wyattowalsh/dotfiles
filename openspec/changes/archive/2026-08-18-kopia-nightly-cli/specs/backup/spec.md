## ADDED Requirements

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

### Requirement: Strict wall-clock ceiling

A normal live nightly run SHALL terminate within twelve hours, including forced-termination grace. Preview, install, doctor, and the private bounded child mode SHALL NOT recursively enter the wall-clock wrapper.

#### Scenario: Normal run is externally bounded

- **WHEN** the public runner starts normal snapshot work
- **THEN** it delegates that work through `/opt/homebrew/bin/gtimeout`
- **AND** TERM is sent after 43,140 seconds
- **AND** KILL is permitted 60 seconds later
- **AND** the total hard boundary is 43,200 seconds

#### Scenario: LaunchAgent expresses only stop grace

- **WHEN** the nightly LaunchAgent plist is rendered
- **THEN** it does not contain the unimplemented `TimeOut` key
- **AND** it sets `ExitTimeOut` to 120 seconds

### Requirement: Bounded repository readiness

Repository readiness SHALL be probed without allowing one hung status command to consume the whole run.

#### Scenario: Status command hangs

- **WHEN** a `kopia repository status` attempt exceeds 30 seconds
- **THEN** it receives TERM and may receive KILL five seconds later
- **AND** its output remains discarded
- **AND** the timeout counts as a failed attempt rather than stopping the retry loop

#### Scenario: Readiness is exhausted

- **WHEN** eight status attempts fail or time out
- **THEN** the delays after failures are bounded to `5, 10, 20, 30, 30, 30, 30` seconds
- **AND** the run terminates as an operational failure

### Requirement: Deterministic lifecycle finalization

Catchable termination and ordinary exit SHALL pass through one idempotent finalizer whose state remains valid after the work function returns.

#### Scenario: Successful or failed ordinary exit

- **WHEN** the bounded child exits normally
- **THEN** one EXIT finalizer clears its traps before cleanup
- **AND** it re-disables both KopiaUI login labels before other cleanup
- **AND** an absent optional process identifier cannot trigger an unbound-variable failure

#### Scenario: TERM or INT

- **WHEN** the runner receives TERM or INT
- **THEN** it records the signal outcome and exits through the finalizer
- **AND** TERM resolves to status 143
- **AND** INT resolves to status 130

#### Scenario: Caffeinate lifetime

- **WHEN** `caffeinate -w` follows the runner process
- **THEN** the finalizer does not manually kill a stored caffeinate PID
- **AND** cleanup cannot signal an unrelated process after PID reuse

#### Scenario: Cleanup fails

- **WHEN** final cleanup fails after otherwise successful snapshot work
- **THEN** the final result is promoted to an operational failure

### Requirement: Single outcome notification

Catchable terminal outcomes SHALL emit no more than one bounded, best-effort desktop notification using static text that contains no secret or repository output.

#### Scenario: Everything succeeds

- **WHEN** snapshots, full maintenance, and cleanup succeed
- **THEN** the runner exits zero without a desktop notification

#### Scenario: Maintenance alone fails

- **WHEN** every snapshot and cleanup succeeds but `kopia maintenance run --full` fails
- **THEN** the runner exits zero
- **AND** it emits exactly one warning notification

#### Scenario: Operational work fails

- **WHEN** readiness, wake/rclone handling, a snapshot, lifecycle handling, or cleanup fails
- **THEN** the runner exits nonzero
- **AND** it emits exactly one failure notification

#### Scenario: Multiple outcome classes fail

- **WHEN** operational work, maintenance, or cleanup failures overlap
- **THEN** the runner emits one combined failure notification rather than multiple notifications

#### Scenario: Notification fails or hangs

- **WHEN** desktop notification cannot complete within its bounded interval
- **THEN** notification failure does not replace the primary run status

### Requirement: Nightly contract is regression-tested offline

The repository SHALL validate timeout, lifecycle, progress, locking, maintenance, and notification behavior without touching the real backup repository or user LaunchAgents.

#### Scenario: Static contract check

- **WHEN** `checks/kopia-nightly.sh` runs
- **THEN** it rejects an unbounded repository-status probe
- **AND** it rejects unconditional `--progress`
- **AND** it rejects loss of the single-run lock
- **AND** it rejects a fatal maintenance-only failure
- **AND** it rejects a plist `TimeOut` key

#### Scenario: Stubbed behavior matrix

- **WHEN** the offline runner fixtures execute
- **THEN** they cover success, readiness exhaustion, per-attempt timeout, snapshot failure, maintenance warning, cleanup failure, TERM, INT, and notification failure
- **AND** they never call the real Kopia repository, launchctl service, or desktop notification service
