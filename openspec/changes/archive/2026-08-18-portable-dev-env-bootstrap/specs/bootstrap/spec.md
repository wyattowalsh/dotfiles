## ADDED Requirements

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
