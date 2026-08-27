## ADDED Requirements

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

### Requirement: Fail-closed backup status

`--storage-plan` SHALL report Kopia as reachable, verify-unknown, or not installed from a timed `kopia repository status` without password flags. Time Machine listing on Darwin is report-only. Failure SHALL NOT fail the storage-plan exit (exit 0 unless unrelated errors). Unique-cold reclaim SHALL NOT be recommended while verify is unknown.

#### Scenario: Kopia missing

- **WHEN** `kopia` is not on PATH
- **THEN** `--storage-plan` prints that Kopia is not installed and exits 0

#### Scenario: Kopia status fails

- **WHEN** `kopia repository status` returns non-zero
- **THEN** `--storage-plan` prints verify-unknown and exits 0

### Requirement: Companion next actions are text

When `mo` is on PATH, `--storage-plan` Next Actions MAY mention `mo clean -n`. freshen SHALL NOT execute Mole or files-buddy.

#### Scenario: Mole mentioned not run

- **WHEN** `mo` is on PATH during `--storage-plan`
- **THEN** output mentions `mo clean -n`
- **AND** the command trace does not contain a `mo` invocation


#### Scenario: Labels are rows not legend

- **WHEN** `$HOME/Library/Caches` exists and `FRESHEN_STORAGE_SCAN_SURFACES` is unset
- **THEN** output includes a `cache-prune` row for that path and a restore hint
- **AND** output includes `Skipped broad surface sizing`

#### Scenario: Unique-cold polarity

- **WHEN** Kopia is missing or `kopia repository status` is non-zero
- **THEN** `--storage-plan` prints that unique-cold reclaim is not recommended
- **AND** when `kopia repository status` succeeds, that not-recommended line is absent

#### Scenario: Docker info failure skips df

- **WHEN** docker is on PATH and `docker info` fails
- **THEN** freshen SHALL NOT run `docker system df`

#### Scenario: Find walks the canonical prune root

- **WHEN** `--dev-prune-root` is a safe directory
- **THEN** `find` is invoked on the canonical (`:A`) root with `-P`
