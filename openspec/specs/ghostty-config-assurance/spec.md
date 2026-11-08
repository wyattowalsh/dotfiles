# ghostty-config-assurance Specification

## Purpose
TBD - created by archiving change improve-ghostty-config-assurance. Update Purpose after archive.
## Requirements
### Requirement: Canonical Ghostty template

The repository SHALL manage Ghostty through `rig/home/private_dot_config/ghostty/private_config.tmpl` with a private (`0600`) deployed file, retain the public theme/font data contract, and load an optional machine-local overlay using the sibling-relative `config-file = ?config.local` directive.

#### Scenario: Render the tracked base config

- **WHEN** the Ghostty template is rendered with the tracked Chezmoi source and data
- **THEN** the result contains no unresolved template expressions
- **AND** the optional overlay resolves beside the rendered configuration
- **AND** absence of `config.local` does not fail rendering or Ghostty parsing

#### Scenario: Keep the deployed file private

- **WHEN** Chezmoi applies only the Ghostty configuration target
- **THEN** `~/.config/ghostty/config` has mode `0600`
- **AND** the optional local overlay and background assets are not overwritten

#### Scenario: Keep machine paths portable in source

- **WHEN** the tracked Ghostty template is inspected
- **THEN** it contains no literal `/Users/` path
- **AND** machine-specific background and sound paths use `.chezmoi.homeDir`

### Requirement: Refined Ghostty 1.3 behavior

The tracked Ghostty template SHALL retain intentional explicit settings and SHALL enable harmonious generated palettes, a native macOS titlebar and fullscreen mode for usable tabs, and URL copying through `cmd+alt+u`.

#### Scenario: Validate approved configuration additions

- **WHEN** the rendered base config is parsed by Ghostty 1.3.1 or newer
- **THEN** `palette-harmonious = true` is active with palette generation
- **AND** `macos-titlebar-style = native` and `macos-non-native-fullscreen = false` are accepted
- **AND** `cmd+alt+u` maps to `copy_url_to_clipboard`

#### Scenario: Preserve tab visibility in fullscreen

- **WHEN** the tracked macOS configuration is inspected
- **THEN** it avoids the custom integrated tabs titlebar that stacks and clips tabs on macOS 27 with Ghostty 1.3.1
- **AND** fullscreen does not use a non-native mode that removes the titlebar required for tabs
- **AND** a new window with multiple tabs is visually checked during post-apply acceptance

#### Scenario: Keep clipboard and update ownership intentional

- **WHEN** the tracked Ghostty configuration is inspected
- **THEN** `copy-on-select = true` still writes selections to the macOS system clipboard when no separate selection clipboard exists
- **AND** `selection-clear-on-copy = false` retains the selection after an explicit copy
- **AND** `auto-update = off` delegates app updates to the tracked Homebrew cask workflow

#### Scenario: Keep grapheme widths and padding consistent

- **WHEN** the tracked Ghostty configuration is inspected
- **THEN** `grapheme-width-method = unicode` is explicitly selected
- **AND** the existing horizontal 12-point and vertical 10-point window padding remains balanced pending a visual comparison

#### Scenario: Avoid unsupported padding syntax

- **WHEN** the tracked Ghostty template is checked
- **THEN** it does not contain the invalid `window-padding-color = extend-background` directive

### Requirement: Official shell integration ownership

Ghostty SHALL own automatic integration for the initial zsh through `shell-integration = detect`, and the tracked zsh runtime mirrors SHALL NOT source a custom Ghostty shell-integration file.

#### Scenario: Start an initial zsh in Ghostty

- **WHEN** Ghostty launches the configured initial zsh
- **THEN** official automatic shell integration is selected by Ghostty configuration
- **AND** the zsh runtime does not inspect or source `~/.config/ghostty/shell-integration.zsh`

#### Scenario: Preserve zsh mirror parity

- **WHEN** the tracked runtime zsh files are compared
- **THEN** `rig/dots/zshrc` and `rig/home/dot_zshrc.tmpl` are byte-identical
- **AND** the existing Cursor shell-integration conditional remains present

### Requirement: Focused Ghostty source contract

The repository SHALL provide `checks/ghostty.sh` to enforce the Ghostty template, data, zsh ownership, workflow wiring, and documentation contracts without applying configuration or accessing local assets.

#### Scenario: Run static validation without optional tools

- **WHEN** `checks/ghostty.sh` runs without Ghostty or Chezmoi installed
- **THEN** all static source contracts run
- **AND** only rendered native parsing is reported as skipped
- **AND** the check succeeds only if all static contracts pass

#### Scenario: Report multiple source regressions

- **WHEN** more than one static Ghostty contract is violated
- **THEN** the check reports each affected contract before exiting nonzero

### Requirement: Isolated rendered Ghostty validation

When both `chezmoi` and `ghostty` are available, the focused check SHALL render the tracked template into a private temporary directory and SHALL validate that file through Ghostty's native parser.

#### Scenario: Parse an isolated rendered base config

- **WHEN** `just check-ghostty` runs with both required binaries available
- **THEN** Chezmoi renders the tracked template into a temporary file
- **AND** no real machine-local `config.local` is copied beside it
- **AND** `ghostty +validate-config --config-file=<rendered-path>` succeeds
- **AND** the temporary directory is removed when the check exits

#### Scenario: Fail closed when available tooling rejects source

- **WHEN** Chezmoi rendering or Ghostty parsing fails while both binaries are available
- **THEN** `just check-ghostty` exits nonzero with an actionable diagnostic

### Requirement: Discoverable Ghostty validation workflow

The Ghostty source contract SHALL be available through a focused Just recipe, the aggregate validation suite, shell-file coverage, a path-scoped pre-commit hook, scoped agent guidance, and operator documentation.

#### Scenario: Run focused validation

- **WHEN** `just check-ghostty` is run
- **THEN** it executes `checks/ghostty.sh`

#### Scenario: Change a Ghostty-related source

- **WHEN** pre-commit evaluates a configured Ghostty template, data, zsh, check, workflow, agent-guidance, or operator-doc path
- **THEN** the focused Ghostty source contract runs without receiving filenames

#### Scenario: Consult operator documentation

- **WHEN** an operator reads the terminal, validation, home-config, or shell runbook
- **THEN** the docs distinguish tracked-source validation from deployed-config validation
- **AND** they describe the relative local overlay and the approved Ghostty behavior trade-offs
