## ADDED Requirements

### Requirement: Justfile Orchestration

The repository SHALL expose bootstrap, validation, inventory, docs, package, AI, and secrets workflows through `justfile`.

#### Scenario: Run aggregate checks

- **WHEN** `just check` is run
- **THEN** shell syntax, shell lint, zsh runtime syntax, JSON validation, and secret scanning are executed without mutating managed files.

#### Scenario: Run CI checks

- **WHEN** `just ci` is run
- **THEN** static checks, smoke checks, AI/MCP validation, docs dependency installation, docs typechecking, and docs production build validation are executed.

#### Scenario: Generate redacted local inventory

- **WHEN** `just inventory-redacted` is run
- **THEN** local inventory artifacts are written under ignored `local/` paths.
- **AND** zsh override, function, completion, and custom plugin surfaces are reported by scrubbed path only without copying file contents or environment values into tracked files.

#### Scenario: Scan hidden tracked configuration

- **WHEN** `just secrets-scan` is run
- **THEN** tracked dot-directories such as `.github`, `.claude`, `.copilot`, and `.config` are included while untracked local files, VCS metadata, and generated local artifacts remain excluded.
- **AND** secret-shaped matches are reported by filename without printing matching secret-shaped values.

#### Scenario: Preserve existing user files during setup

- **WHEN** `./setup.sh` is run and a managed dotfile target already exists as a non-symlink
- **THEN** setup fails with an actionable conflict message instead of overwriting or silently skipping the path.

### Requirement: macOS Full Rig Bootstrap

The repository SHALL include a macOS bootstrap path that can run in dry-run mode before installing or linking anything.

#### Scenario: Preview macOS setup

- **WHEN** `just bootstrap --dry-run` is run on macOS
- **THEN** planned Homebrew, Nix, Chezmoi, just, docs, and config steps are printed without changing system state.

#### Scenario: Use pinned nix-darwin fallback

- **WHEN** `just bootstrap --apply` needs nix-darwin and `darwin-rebuild` is not already installed
- **THEN** the bootstrap uses the pinned nix-darwin revision from `darwin/flake.lock`.
- **AND** if `darwin/flake.lock` is missing, setup fails before applying system changes with an actionable lock-generation command instead of resolving a moving branch.

### Requirement: Secret-Safe AI Config

The repository SHALL model AI and MCP client configuration through sanitized manifests with placeholders for secrets.

#### Scenario: Scan AI manifests

- **WHEN** `just ai-check` is run
- **THEN** manifests validate as JSON and no literal MCP bearer token is accepted.
