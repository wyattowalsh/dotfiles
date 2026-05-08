## ADDED Requirements

### Requirement: Taskfile Orchestration
The repository SHALL expose bootstrap, validation, inventory, docs, package, AI, and secrets workflows through `Taskfile.yml`.

#### Scenario: Run aggregate checks
- **WHEN** `task check` is run
- **THEN** shell syntax, shell lint, JSON validation, and secret scanning are executed without mutating managed files.

### Requirement: macOS Full Rig Bootstrap
The repository SHALL include a macOS bootstrap path that can run in dry-run mode before installing or linking anything.

#### Scenario: Preview macOS setup
- **WHEN** `task bootstrap -- --dry-run` is run on macOS
- **THEN** planned Homebrew, Nix, Chezmoi, Task, docs, and config steps are printed without changing system state.

### Requirement: Secret-Safe AI Config
The repository SHALL model AI and MCP client configuration through sanitized manifests with placeholders for secrets.

#### Scenario: Scan AI manifests
- **WHEN** `task ai:check` is run
- **THEN** manifests validate as JSON and no literal MCP bearer token is accepted.

