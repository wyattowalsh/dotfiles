## ADDED Requirements

### Requirement: Fail-fast source traversal

The nightly runner SHALL use Kopia's native fail-fast behavior for each source
and SHALL retain a failed result when any source fails. It SHALL attempt later
configured roots while the existing shared wall-clock budget remains, without
adding exclusions or a separate per-source budget.

#### Scenario: Unreadable source file

- **WHEN** a source contains an unreadable file and Kopia returns failure
- **THEN** the runner records that source as failed
- **AND** it attempts the next configured root while shared time remains
- **AND** the overall run remains unsuccessful and does not enter maintenance
- **AND** it does not report the failed source as complete coverage

#### Scenario: Shared cap reached

- **WHEN** a snapshot returns wall-clock timeout status `124` or `137`
- **THEN** the runner stops the snapshot loop without retrying
- **AND** the default whole-run budget remains 43200 seconds

#### Scenario: Progress arguments

- **WHEN** the runner creates a snapshot
- **THEN** it requests native fail-fast behavior
- **AND** it requests interactive progress only when stdout is a terminal and the process is outside launchd

### Requirement: Diagnostic-specific snapshot retry

The nightly runner SHALL retry an unsuccessful snapshot only when the captured
output matches the native structured rclone startup-timeout diagnostic. It SHALL
allow at most three total attempts using the remaining shared budget.

#### Scenario: Genuine startup timeout

- **WHEN** an unsuccessful snapshot emits the native structured rclone startup-timeout diagnostic
- **THEN** the runner retries only while fewer than three total attempts have run and shared time remains

#### Scenario: Misleading filename or unknown error

- **WHEN** a failed snapshot reports a file-read error whose filename contains `rclone` and `timeout`, or an unknown error
- **THEN** the runner does not classify it as a transport startup timeout
- **AND** it records the source failure without a transport retry
