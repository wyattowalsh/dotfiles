# bootstrap Specification

## Purpose

Justfile orchestrates macOS and Linux bootstrap, validation, inventory, and the portable agent-dev-env wrapper. AI/MCP harness configs live in wyattowalsh/agents.

## Requirements

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

### Requirement: Portable agent-dev-env entrypoint

The repository SHALL expose a dry-run-default agent-stack installer that locates wyattowalsh/agents and does not vendor harness or MCP client configs.

#### Scenario: Preview agent stack

- **WHEN** `just bootstrap-dev` is run with no arguments, or with `--dry-run`
- **THEN** the justfile injects `--dry-run` when the argument list is empty
- **AND** planned agent-stack actions are printed without mutating this repo's machine desired-state files

#### Scenario: Missing agents checkout

- **WHEN** `just bootstrap-dev` is run and no agents checkout is found
- **THEN** the command exits non-zero with clone / `WAGENTS_REPO_ROOT` guidance
- **AND** it does not write MCP JSON under `rig/`

### Requirement: Linux setup delegates the agent stack

Linux `setup.sh` SHALL install AI CLI packages as before, then delegate harness projection to `rig/bootstrap/dev-env.sh` with `--skip-mcphub`. Apply SHALL fail if the wrapper is missing or the installer exits non-zero. Smoke SHALL fail if the wrapper file is missing.

#### Scenario: No hardcoded skills list

- **WHEN** `./setup.sh --dry-run` is run
- **THEN** setup does not invoke `npx skills add` with a hardcoded skill-name list
- **AND** it still plans AI CLI installs and shims
- **AND** the delegated installer is invoked with `--skip-mcphub`

#### Scenario: Apply fail-close

- **WHEN** `./setup.sh` apply mode is run and `rig/bootstrap/dev-env.sh` is missing or exits non-zero
- **THEN** setup exits non-zero
- **AND** `run_dev_env` captures the wrapper status with `set +e` / `rc=$?` (a failed `if cmd; then` MUST NOT be treated as success)

### Requirement: Fleet platforms stay in sync

The installer SHALL pass `sync_agent_stack.py --platforms` using exact `platform_filter_allows` names. First-class fleet is `repo-core,cursor,claude-code,codex,grok,opencode`. It SHALL NOT remap `claude-code` to `claude`, `gemini-cli` to `gemini`, or `github-copilot` to `copilot`.

#### Scenario: Auto fleet CSV

- **WHEN** Cursor, Claude Code, Codex, Grok, and OpenCode are detected
- **THEN** the planned command includes `--platforms repo-core,cursor,claude-code,codex,grok,opencode`

#### Scenario: MCPHub is opt-in

- **WHEN** the installer is run without `--mcphub`
- **THEN** it does not start MCPHub
- **AND** `--mcphub` plans `scripts/mcphub/start-local-only.sh` with the tunnel disabled

### Requirement: macOS bootstrap stays machine-first

Default macOS bootstrap SHALL not apply the agent stack unless `--with-dev-env` is passed.

#### Scenario: Default macOS apply

- **WHEN** `just bootstrap --apply` is run without `--with-dev-env`
- **THEN** brew/nix/chezmoi/dots phases run as before
- **AND** the log names `just bootstrap-dev --dry-run` as a separate next step
