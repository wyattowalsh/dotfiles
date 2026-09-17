# freshen Specification

## Purpose

`freshen` is the zsh autoload that upgrades Homebrew formulae and casks, then Mac App Store apps, then cleanup, caches, and doctor. Interactive TTYs get a two-pane live dashboard; `--progress=plain --no-color` stays the a11y and automation contract. `--storage-plan` is report-only storage advice. `--dev-prune` is the only path that may trash project caches, and only through `gomi`.

## Requirements

### Requirement: Skip-casks file and env

Cask upgrades SHALL drop tokens listed in `$XDG_CONFIG_HOME/freshen/skip-casks` (fallback `~/.config/freshen/skip-casks`) or in `FRESHEN_SKIP_CASKS`. Missing skip files SHALL NOT fail freshen. Spotify is a pinned skip-casks token.

#### Scenario: Skip file drops a cask

- **GIVEN** `~/.config/freshen/skip-casks` contains `spotify`
- **WHEN** cask inventory would otherwise include `spotify`
- **THEN** `spotify` is not passed to cask upgrade

### Requirement: Live dashboard is a two-pane framed board

On an interactive TTY with `--progress=auto` or `--progress=live` (and not `plain`), the live dashboard SHALL paint a rounded box containing a PHASES rail of all phases and a NOW pane for the in-flight lane (name, optional package, truncated last child line, elapsed). It SHALL NOT be solely seven unboxed `icon Phase: status` lines.

#### Scenario: Live dump is a dashboard

- **WHEN** `freshen` runs with live enabled under test (`FRESHEN_FORCE_LIVE=1` and `FRESHEN_UNDER_TEST` set)
- **THEN** stdout includes the labels `PHASES` and `NOW` and a rounded box drawing character

#### Scenario: Live dump is not the old seven-row list

- **WHEN** the same live run is captured
- **THEN** the dump is not only the previous unboxed seven-row phase list

### Requirement: NOW includes a discovery progress graph

After inventory discovers outdated formulae, casks, or apps, the NOW pane SHALL render an OVERALL graph that fans out from inventory into per-package nodes for those lanes and merges into cleanup → caches → doctor. Node count SHALL grow with discovered packages.

#### Scenario: Discovered cask and formula become graph nodes

- **WHEN** a live dry-run inventories outdated `wget` and `firefox`
- **THEN** stdout includes `OVERALL` plus those package names as graph nodes

### Requirement: Recap reuses live chrome

After live closes, a non-dry-run recap SHALL use the same outer rounded box, with Attention and Next actions before the phase Summary. Honesty status words SHALL remain the existing tokens.

#### Scenario: Degraded apply recap is boxed

- **WHEN** a degraded apply run used live
- **THEN** the recap region after the last alt-screen leave includes the box and Attention-first order

### Requirement: plain is not the dashboard

`--progress=plain` (and `FRESHEN_LOW_POWER=1`) SHALL NOT emit box drawing or live pane labels.

#### Scenario: plain apply has no dashboard chrome

- **WHEN** `freshen --progress=plain --no-color --yes` runs under test
- **THEN** stdout contains no `╭` and no `PHASES`/`NOW` pane chrome

### Requirement: Busy lock offers replace

When another live freshen holds the instance lock, an interactive run SHALL list the holder and offer to take the lock. `--replace` SHALL take the lock without a TTY. A login shell holder SHALL NOT be SIGKILL'd.

#### Scenario: Non-interactive lock stays blocked

- **WHEN** a second non-interactive freshen hits a live lock
- **THEN** it exits non-zero and points at a TTY or `--replace`

### Requirement: Age-gated dev-prune

`--dev-prune` SHALL skip project-cache directories whose mtime is newer than `FRESHEN_DEV_PRUNE_MIN_AGE_DAYS` days (default 14). A value of `0` SHALL disable the age skip. Dry-run SHALL NOT call `gomi`. Execution SHALL still require `gomi` and SHALL NOT fall back to `rm`.

#### Scenario: Skip a fresh cache

- **WHEN** `--dev-prune` runs against a `node_modules` directory created now and the min-age env is default
- **THEN** that directory is not passed to `gomi`
- **AND** the plan reports it as skipped-recent

#### Scenario: Trash a stale cache

- **WHEN** `--dev-prune --yes` runs with `gomi` available against a `node_modules` whose mtime is older than the min-age
- **AND** the directory is not a live workspace
- **THEN** `gomi --` is invoked with that path

#### Scenario: Disable age skip

- **WHEN** `FRESHEN_DEV_PRUNE_MIN_AGE_DAYS=0`
- **THEN** a freshly created matching cache is eligible (subject to live-workspace and root safety)

#### Scenario: Find walks the canonical prune root

- **WHEN** `--dev-prune-root` is a safe directory
- **THEN** `find` is invoked on the canonical (`:A`) root with `-P`

### Requirement: Live-workspace skip

`--dev-prune` SHALL skip a candidate that is the current working directory, an ancestor of it, or a descendant of it unless the working directory is the prune root itself.

#### Scenario: CWD is the cache

- **WHEN** freshen is invoked with cwd equal to a candidate `node_modules` under the prune root
- **THEN** that candidate is not passed to `gomi`

#### Scenario: Explicit broad prune root

- **WHEN** cwd equals `--dev-prune-root` and that root is safe (not `$HOME` or `/`)
- **THEN** descendant caches are not skipped solely for living under cwd
- **AND** age and root-safety rules still apply

### Requirement: Storage-plan stays report-only

`--storage-plan` SHALL NOT upgrade brew/mas, SHALL NOT clean package-manager caches, SHALL NOT run `docker system prune`, SHALL NOT run `nix store gc` without `--dry-run`, SHALL NOT invoke `mo`, and SHALL NOT pass a Kopia password on argv.

#### Scenario: No Homebrew required

- **WHEN** `--storage-plan` runs without `brew` on PATH
- **THEN** the command exits 0 and prints a storage plan

#### Scenario: Docker probe is non-mutating

- **WHEN** docker is present and `docker info` succeeds during `--storage-plan`
- **THEN** freshen may run `docker system df`
- **AND** it SHALL NOT run `docker system prune`

#### Scenario: Docker info failure skips df

- **WHEN** docker is on PATH and `docker info` fails
- **THEN** freshen SHALL NOT run `docker system df`

### Requirement: Classified surfaces

`--storage-plan` SHALL label listed surfaces with an action class (`cache-prune`, `review`, or `report-only`) and a restore hint. Labels SHALL print even when `FRESHEN_STORAGE_SCAN_SURFACES` is unset. Unique-model, app-library, Kopia, and docker-volume paths that exist under `$HOME` SHALL appear as report-only / do-not-touch, not as prune recommendations.

#### Scenario: Labels without sizing

- **WHEN** `--storage-plan` runs without `FRESHEN_STORAGE_SCAN_SURFACES=1`
- **THEN** output includes action-class labels
- **AND** it does not require a successful `du` of `$HOME/Library/Caches`

#### Scenario: Unique model is report-only

- **WHEN** `$HOME/Library/Application Support/LM Studio` exists
- **THEN** `--storage-plan` labels it report-only / unique-model
- **AND** it does not call `gomi` for that path

#### Scenario: Labels are rows not legend

- **WHEN** `$HOME/Library/Caches` exists and `FRESHEN_STORAGE_SCAN_SURFACES` is unset
- **THEN** output includes a `cache-prune` row for that path and a restore hint
- **AND** output includes `Skipped broad surface sizing`

### Requirement: Fail-closed backup status

`--storage-plan` SHALL report Kopia as reachable, verify-unknown, or not installed from a timed `kopia repository status` without password flags. Time Machine listing on Darwin is report-only. Failure SHALL NOT fail the storage-plan exit (exit 0 unless unrelated errors). Unique-cold reclaim SHALL NOT be recommended while verify is unknown or while per-source coverage is incomplete.

#### Scenario: Kopia missing

- **WHEN** `kopia` is not on PATH
- **THEN** `--storage-plan` prints that Kopia is not installed and exits 0

#### Scenario: Kopia status fails

- **WHEN** `kopia repository status` returns non-zero
- **THEN** `--storage-plan` prints verify-unknown and exits 0

#### Scenario: Unique-cold polarity

- **WHEN** Kopia is missing or `kopia repository status` is non-zero
- **THEN** `--storage-plan` prints that unique-cold reclaim is not recommended
- **AND** when `kopia repository status` succeeds but expected sources lack a non-zero snapshot, that not-recommended line remains
- **AND** the not-recommended line is absent only when status succeeds and every expected source has a non-zero latest snapshot

### Requirement: Companion next actions are text

When `mo` is on PATH, `--storage-plan` Next Actions MAY mention `mo clean -n`. freshen SHALL NOT execute Mole or files-buddy.

#### Scenario: Mole mentioned not run

- **WHEN** `mo` is on PATH during `--storage-plan`
- **THEN** output mentions `mo clean -n`
- **AND** the command trace does not contain a `mo` invocation

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
