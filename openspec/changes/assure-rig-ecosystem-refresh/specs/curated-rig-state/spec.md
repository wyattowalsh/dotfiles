## ADDED Requirements

### Requirement: tmux ownership remains explicit

Homebrew desired state SHALL either record tmux as intentionally unmanaged or bind it to an exact tracked consumer so inventory promotion cannot silently restore an unexplained formula.

#### Scenario: Brew inventory reconciliation

- **WHEN** the live formula inventory contains tmux but the curated Brewfile does not
- **THEN** `rig/brew/exclude.txt` contains `tmux`
- **AND** the Brew exclusion check treats that difference as intentional

#### Scenario: Agent Deck owns tmux

- **WHEN** the curated Brewfile declares `brew "tmux"`
- **THEN** it also declares `brew "asheshgoplani/tap/agent-deck"`
- **AND** `rig/brew/exclude.txt` does not contradict that managed dependency

### Requirement: Notebook diff attributes have a provider

Global notebook Git attributes SHALL be paired with the nbdime command provider in package desired state.

#### Scenario: Notebook attributes are active

- **WHEN** tracked Git attributes assign nbdime to `*.ipynb`
- **THEN** the Brewfile declares `uv "nbdime"`
- **AND** the existing nbdime Git driver configuration remains parseable

### Requirement: macOS defaults match the approved G0 through G3 set

The nix-darwin configuration SHALL retain approved G0 through G3 behavior and SHALL NOT include the unapproved G4 guest-login or WindowManager defaults.

#### Scenario: G4 is absent

- **WHEN** the macOS defaults module is evaluated or statically checked
- **THEN** it does not set `loginwindow.GuestEnabled`
- **AND** it does not set `WindowManager.GloballyEnabled`
- **AND** it does not set `WindowManager.EnableStandardClickToShowDesktop`

### Requirement: Git configuration excludes unapproved D6 wiring

The tracked Git configuration SHALL preserve approved D1 through D5 behavior without the unapproved difftastic alias or difftool wiring.

#### Scenario: D6 is absent

- **WHEN** the tracked Git configuration is parsed
- **THEN** it contains no `dft` alias
- **AND** it contains no difftastic difftool block introduced by D6
- **AND** removal does not require deleting the independently retained difftastic formula

### Requirement: Refresh contracts have focused regression coverage

Deterministic checks SHALL pin the reviewed shell, Yazi, Brew, Git, and nix-darwin invariants in addition to aggregate repository checks.

#### Scenario: A reviewed invariant regresses

- **WHEN** plugin count/order, history sizing, pnpm completion, YSU source, Yazi field/lock/key, tmux ownership, nbdime provider, G4 absence, or D6 absence deviates
- **THEN** a focused check fails with the affected invariant identified

### Requirement: Operator documentation matches desired state

Human runbooks SHALL describe the final reviewed behavior and use copyable current commands.

#### Scenario: Affected docs are validated

- **WHEN** docs CI and hub-parity checks run
- **THEN** package grouping (including gitleaks), Git behavior and hub copy, nbdime, Yazi package specs/flavors/keys, direnv modes, explicit tmux ownership, approved macOS defaults, and shell plugin ordering match tracked desired state
- **AND** Yazi package commands use fully qualified `yazi-rs/plugins:<name>` specs
- **AND** Ghostty documentation describes both `font-feature = calt` and `font-feature = -liga`
- **AND** backup documentation uses stable LaunchAgent-label language rather than a transient Login Items UI string
- **AND** docs do not describe the reverted G4 or D6 behavior as active
