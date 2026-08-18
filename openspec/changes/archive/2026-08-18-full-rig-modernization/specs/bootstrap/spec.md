## ADDED Requirements

### Requirement: Justfile Orchestration

The repository SHALL expose bootstrap, validation, inventory, docs, package, and secrets workflows through `justfile`.

#### Scenario: Run aggregate checks

- **WHEN** `just check` is run
- **THEN** the following static gates run without mutating managed files: `check-hooks`, `check-shell`, `check-zsh`, `check-freshen`, `check-json`, `secrets-scan`, `brew-exclude`, `check-stale-paths`, `check-kopia-nightly`, `check-chezmoi-ignore`, `check-darwin-lock`, `check-linux-dev-env-rc`, and `check-shell-files`.

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
- **AND** the pin SHALL be recoverable from github `locked.owner` / `repo` / `rev` **or** a tarball `locked.url` archive SHA plus `original.owner` / `repo`.
- **AND** if `rig/darwin/flake.lock` is missing, setup fails before applying system changes with an actionable lock-generation command instead of resolving a moving branch.

### Requirement: Platform bootstrap dispatch

`just bootstrap` SHALL exec `rig/bootstrap/macos.sh` on Darwin and `rig/bootstrap/linux.sh` on Linux. Other kernels SHALL fail with an actionable error. Linux setup SHALL mutate by default (no `--apply` flag); macOS SHALL default to dry-run unless `--apply` is passed.

#### Scenario: Linux just bootstrap

- **WHEN** `just bootstrap --dry-run` is run on Linux
- **THEN** execution reaches `rig/bootstrap/linux.sh` with the same flags
- **AND** it does not invoke `rig/bootstrap/macos.sh`

### Requirement: External AI Harness SSOT

AI and MCP client configuration SHALL live in `wyattowalsh/agents`. This repository MAY document env var names in `.env.example` only.

#### Scenario: Env names only

- **WHEN** an agent documents AI or MCP credentials in this repository
- **THEN** only environment variable names appear (for example in `.env.example`)
- **AND** harness JSON, client manifests, and secret values are not committed here
