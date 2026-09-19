## ADDED Requirements

### Requirement: Oh My Zsh exclusively initializes completion
The managed zsh runtime SHALL assemble all completion paths before sourcing Oh My Zsh and SHALL NOT invoke `compinit` directly.

#### Scenario: Managed shell starts completion once
- **WHEN** a new interactive shell sources the canonical zshrc
- **THEN** Grok, CCS, pnpm, Docker, and local completion paths are present before Oh My Zsh initializes completion
- **AND** no user-owned `compinit` call runs afterward

#### Scenario: Installer appends another compinit
- **WHEN** direct `compinit` text appears in the canonical zshrc
- **THEN** the zsh structure gate fails

### Requirement: Completion directories remain secure
The macOS bootstrap SHALL inspect completion paths with `compaudit`, SHALL remove group/world write bits from reported directories in apply mode, and SHALL verify that no findings remain. Dry-run SHALL NOT change permissions.

#### Scenario: Homebrew share is group-writable
- **WHEN** `/opt/homebrew/share` is reported by `compaudit` during bootstrap apply
- **THEN** bootstrap applies `chmod go-w` and reruns the audit

#### Scenario: A finding cannot be repaired by mode normalization
- **WHEN** `compaudit` still reports a path after bootstrap normalization
- **THEN** bootstrap exits the phase with the remaining paths and a failure

#### Scenario: Static validation runs on macOS
- **WHEN** `just check-zsh` runs on Darwin
- **THEN** `checks/zsh-compaudit.sh` fails if `compaudit` reports any path

#### Scenario: Static validation runs on Linux CI
- **WHEN** `checks/zsh-compaudit.sh` runs on a non-Darwin host
- **THEN** it exits successfully with an explicit skip message

### Requirement: Completion dumps use XDG cache
The managed zsh runtime SHALL set `ZSH_COMPDUMP` beneath `${XDG_CACHE_HOME:-$HOME/.cache}/zsh` with host and zsh-version discrimination.

#### Scenario: New shell initializes completion cache
- **WHEN** the XDG zsh cache directory is absent
- **THEN** startup creates the directory and Oh My Zsh writes its completion dump there
- **AND** no new `~/.zcompdump*` file is created

### Requirement: Canonical and mirror configuration remain identical
The runtime zshrc and its Chezmoi validation mirror SHALL remain byte-identical.

#### Scenario: One copy changes independently
- **WHEN** `rig/dots/zshrc` differs from `rig/home/dot_zshrc.tmpl`
- **THEN** `just check-zsh` fails mirror parity
