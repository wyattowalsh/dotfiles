## MODIFIED Requirements

### Requirement: Justfile Orchestration

The repository SHALL expose bootstrap, validation, inventory, docs, package, and secrets workflows through `justfile`.

#### Scenario: Run aggregate checks

- **WHEN** `just check` is run
- **THEN** the following static gates run without mutating managed files: `check-hooks`, `check-shell`, `check-zsh`, `check-freshen`, `check-json`, `secrets-scan`, `brew-exclude`, `check-stale-paths`, `check-kopia-nightly`, `check-ghostty`, `check-chezmoi-ignore`, `check-darwin-lock`, `check-linux-dev-env-rc`, and `check-shell-files`.

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
