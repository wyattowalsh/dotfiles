## ADDED Requirements

### Requirement: Justfile Orchestration

The repository SHALL expose bootstrap, validation, inventory, docs, package, and secrets workflows through `justfile`.

#### Scenario: Run aggregate checks

- **WHEN** `just check` is run
- **THEN** shell syntax, shell lint, zsh runtime syntax, freshen version SSOT smoke, JSON validation, and secret scanning are executed without mutating managed files.

#### Scenario: Run CI checks

- **WHEN** `just ci` is run
- **THEN** static checks, smoke checks, docs dependency installation, docs typechecking, and docs production build validation are executed.

#### Scenario: Generate redacted local inventory

- **WHEN** `just inventory-redacted` is run
- **THEN** local inventory artifacts are written under ignored `local/` paths.
- **AND** zsh override, function, completion, and custom plugin surfaces are reported by scrubbed path only without copying file contents or environment values into tracked files.

#### Scenario: Scan hidden tracked configuration

- **WHEN** `just secrets-scan` is run
- **THEN** all tracked files from `git ls-files` are scanned while untracked local files, VCS metadata, lockfiles, and generated local artifacts remain excluded.
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
- **THEN** the bootstrap uses the pinned nix-darwin revision from `rig/darwin/flake.lock`.
- **AND** if `rig/darwin/flake.lock` is missing, setup fails before applying system changes with an actionable lock-generation command instead of resolving a moving branch.

### Requirement: External AI Harness SSOT

AI and MCP client configuration SHALL live in `wyattowalsh/agents`. This repository MAY document env var names in `.env.example` only.
