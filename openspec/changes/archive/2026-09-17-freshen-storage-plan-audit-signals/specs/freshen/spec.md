# freshen Spec Delta

## ADDED Requirements

### Requirement: Storage-plan named leaf surfaces

`--storage-plan` SHALL emit the existing catalog rows and SHALL also emit named leaf rows for:

- `cache-prune`: `${HOME}/.cache/uv` (note names `uv cache prune`, no dry-run, never `--force`)
- `cache-prune`: `${HOME}/.npm/_npx` (skip if in-use)
- `cache-prune`: `${HOME}/Library/pnpm/store/v11` (note names `pnpm store prune`; v11 store only)
- `review`: `${HOME}/.cache/opencode` (MUST NOT recommend `opencode uninstall`)
- `report-only`: `/Library/Developer/CoreSimulator` (simctl unused runtimes; do-not-delete)
- `report-only`: `${HOME}/Library/CloudStorage` (File Provider; do-not-du)

A missing new leaf SHALL print `absent` and MUST NOT fail `--storage-plan`.

#### Scenario: Catalog includes uv and pnpm store leaves

- **GIVEN** `$HOME/.cache/uv` and `$HOME/Library/pnpm/store/v11` exist
- **WHEN** `--storage-plan` runs
- **THEN** output includes a `cache-prune` row for each path

#### Scenario: OpenCode uninstall is not recommended

- **WHEN** `--storage-plan` prints the OpenCode leaf
- **THEN** the restore hint does not recommend `opencode uninstall`

#### Scenario: Missing leaf is absent not a failure

- **WHEN** `$HOME/.cache/uv` does not exist
- **THEN** `--storage-plan` prints `absent` for that leaf
- **AND** exits 0

### Requirement: Storage-plan parent rows are unsized

`--storage-plan` SHALL NOT pass these paths to `du`: `${HOME}/.cache`, `${HOME}/Library/Caches`, `${HOME}/Library/Developer/CoreSimulator`, `${HOME}/Library/CloudStorage`, `/Library/Developer/CoreSimulator`. Existing leaf cache paths that exist MAY be sized when `FRESHEN_STORAGE_SCAN_SURFACES=1`.

#### Scenario: CloudStorage is never du'd

- **GIVEN** `$HOME/Library/CloudStorage` exists and `FRESHEN_STORAGE_SCAN_SURFACES=1`
- **WHEN** `--storage-plan` runs
- **THEN** `du` is not invoked on `$HOME/Library/CloudStorage`

#### Scenario: Parent .cache is not sized

- **GIVEN** `$HOME/.cache` exists and `FRESHEN_STORAGE_SCAN_SURFACES=1`
- **WHEN** `--storage-plan` runs
- **THEN** `du` is not invoked on `$HOME/.cache` itself

### Requirement: Storage-plan in-use skip

`--storage-plan` SHALL detect processes executing from uv, npm npx, pnpm v11 store, or OpenCode cache by matching the absolute path prefix in `ps -axo pid=,command=` output. It MUST NOT use `pgrep -afil`. If the path is in-use, or the in-use probe fails or times out, the row SHALL display `in-use / skip` and MUST NOT recommend prune or `--force`.

#### Scenario: uv cache in-use is skipped

- **GIVEN** `ps` output contains `${HOME}/.cache/uv`
- **WHEN** `--storage-plan` reports that leaf
- **THEN** the row includes `in-use / skip`
- **AND** the row does not recommend `--force`

#### Scenario: in-use probe failure is fail-closed

- **GIVEN** `ps` exits non-zero
- **WHEN** `--storage-plan` reports a prunable leaf
- **THEN** the row is treated as in-use and prune is not recommended

### Requirement: Storage-plan Kopia source coverage

After a successful timed `kopia repository status` (no password on argv), `--storage-plan` SHALL attempt per-source coverage unless the nightly LaunchAgent `com.wyattowalsh.kopia-nightly` is running (or `FRESHEN_KOPIA_NIGHTLY_RUNNING=1`), in which case it SHALL print that coverage was not probed and unique-cold remains not recommended.

Coverage SHALL use `kopia snapshot list --all --json` with stdout parsed as JSON and stderr discarded. Parse or timeout failure SHALL print `coverage unknown` and unique-cold remains not recommended.

The report SHALL list latest snapshot time, `fileCount`, and `totalSize` for Documents, Movies, Music, Pictures, Public, `dev`, and `src` under `$HOME`. A snapshot with `fileCount` 0 or `totalSize` 0 SHALL be treated as incomplete. The report SHALL print that Downloads is not covered. Unique-cold reclaim SHALL remain not recommended unless the repository is reachable and every expected source has a non-zero latest snapshot.

`--storage-plan` MUST NOT run `kopia snapshot verify` or `kopia maintenance`.

#### Scenario: Downloads is reported uncovered

- **GIVEN** Kopia repository status is reachable
- **AND** nightly is not treated as running
- **WHEN** `--storage-plan` prints backup status
- **THEN** output includes that Downloads is not covered

#### Scenario: zero-file Music snapshot blocks unique-cold

- **GIVEN** Kopia is reachable
- **AND** the latest Music snapshot has `fileCount` 0
- **WHEN** `--storage-plan` prints backup status
- **THEN** unique-cold reclaim is not recommended

#### Scenario: nightly overlap skips coverage

- **GIVEN** `FRESHEN_KOPIA_NIGHTLY_RUNNING=1`
- **WHEN** `--storage-plan` prints backup status
- **THEN** coverage is not probed
- **AND** unique-cold reclaim is not recommended

### Requirement: Storage-plan simctl report-only

On Darwin, `--storage-plan` MAY list unused simulator runtimes via `xcrun simctl runtime list`. It MUST NOT run `simctl runtime delete` or `--notUsedSinceDays 0`. An Xcode license error SHALL print that simctl was skipped and MUST NOT fail `--storage-plan`. The default test harness MUST NOT invoke real `xcrun simctl` unless `FRESHEN_TEST_SIMCTL=1`.

#### Scenario: Xcode license skip is non-fatal

- **GIVEN** `simctl` fails because the Xcode license is not agreed
- **WHEN** `--storage-plan` runs with simctl probing enabled
- **THEN** the command still succeeds
- **AND** output indicates simctl was skipped

### Requirement: Storage-plan claimed-versus-measured footer

`--storage-plan` SHALL print a short footer stating that tool claims, allocated deltas, and measured free space can differ; that `gomi` staged bytes are not confirmed reclaim until trash is emptied; and that `--storage-plan` does not empty trash, delete simulators, invoke `mo`, or offload Drive.

#### Scenario: Footer is present

- **WHEN** `--storage-plan` completes
- **THEN** the footer states staged trash is not confirmed reclaim
- **AND** the footer states `mo` is not invoked

## MODIFIED Requirements

### Requirement: Fail-closed backup status

`--storage-plan` SHALL report Kopia as reachable, verify-unknown, or not installed from a timed `kopia repository status` without password flags. Time Machine listing on Darwin is report-only. Failure SHALL NOT fail the storage-plan exit (exit 0 unless unrelated errors). Unique-cold reclaim SHALL NOT be recommended while verify is unknown **or while per-source coverage is incomplete**.

#### Scenario: Unique-cold polarity

- **WHEN** Kopia is missing or `kopia repository status` is non-zero
- **THEN** `--storage-plan` prints that unique-cold reclaim is not recommended
- **AND** when `kopia repository status` succeeds but expected sources lack a non-zero snapshot, that not-recommended line remains
- **AND** the not-recommended line is absent only when status succeeds and every expected source has a non-zero latest snapshot
