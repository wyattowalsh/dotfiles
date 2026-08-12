# Layout Spec

## ADDED Requirements

### Requirement: Machine desired-state lives under rig/

The repository SHALL place machine desired-state partitions under `rig/`:

- `rig/bootstrap/`
- `rig/dots/`
- `rig/brew/`
- `rig/darwin/`
- `rig/home/`

#### Scenario: Top-level does not host machine partitions

- **WHEN** an agent or operator lists the repository root for machine SSOT
- **THEN** bootstrap, dots, brew, darwin, and home appear under `rig/` and not as top-level peers of `docs/` and `checks/`

### Requirement: Repo process surfaces stay top-level

`docs/`, `checks/`, `openspec/`, `local/`, `.github/`, root `AGENTS.md`, `justfile`, and thin `setup.sh` SHALL remain at the repository root.

#### Scenario: Validation scripts remain discoverable

- **WHEN** CI runs `just ci`
- **THEN** recipes resolve `./checks/*` without nesting under `rig/`

### Requirement: Bootstrap path resolver

Bootstrap scripts under `rig/bootstrap/` SHALL resolve repository root via two parents from the script directory and set `RIG_DIR="$REPO_ROOT/rig"`. Machine paths SHALL use `$RIG_DIR/{brew,darwin,home,dots}`.

#### Scenario: Nested bootstrap finds Brewfile

- **WHEN** `rig/bootstrap/macos.sh` runs
- **THEN** it reads `rig/brew/Brewfile` and links from `rig/dots/*` without treating `rig/` as the repository root

### Requirement: Stable Linux entrypoint

Root `setup.sh` SHALL remain a thin wrapper that execs `rig/bootstrap/linux.sh`.

#### Scenario: Linux operator uses setup.sh

- **WHEN** an operator runs `./setup.sh --dry-run`
- **THEN** execution reaches `rig/bootstrap/linux.sh` with the same CLI flags

### Requirement: Checks resolve machine assets under rig/

Validation scripts under top-level `checks/` SHALL resolve the repository root with one parent directory, then prefix machine paths with `rig/` (for example `rig/home/…`, `rig/brew/…`, `rig/dots/…`).

#### Scenario: freshen smoke finds sources

- **WHEN** `just check-freshen` runs
- **THEN** it reads freshen sources under `rig/home/dot_zsh/functions/`

### Requirement: Contracts do not reintroduce top-level machine partitions

Root `AGENTS.md`, nested `rig/**/AGENTS.md`, and operator docs SHALL describe live machine SSOT under `rig/` and MUST NOT present bare top-level `bootstrap/`, `dots/`, `brew/`, `darwin/`, or `home/` as current locations.

#### Scenario: domain map layout sketch

- **WHEN** an operator reads the domain-map layout sketch
- **THEN** machine partitions appear nested under `rig/`
