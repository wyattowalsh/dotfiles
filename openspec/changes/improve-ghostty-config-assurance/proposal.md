## Why

The tracked Ghostty configuration is already feature-rich, but it lacks a focused render-and-parse gate, uses an unnecessarily absolute optional-overlay include, and retains an inert zsh source branch that no longer owns shell integration. Ghostty 1.3.1 adds useful, validated capabilities that can refine the daily terminal workflow while keeping the existing explicit configuration style.

## What Changes

- Adopt harmonious generated palettes, padded-notch non-native fullscreen, and a URL-copy keybinding in the tracked Ghostty template.
- Change the optional machine-local overlay to the sibling-relative `?config.local` form.
- Remove the dead custom Ghostty shell-integration source branch from both byte-identical zsh runtime mirrors while retaining official `shell-integration = detect` ownership.
- Add `checks/ghostty.sh` with mandatory static contracts and conditional Chezmoi-rendered validation through the installed Ghostty parser.
- Wire the focused gate into Just, the shell-file ledger, pre-commit, scoped agent guidance, and operator documentation.
- Preserve existing explicit Ghostty pins and exclude unrelated visual experiments, local asset tracking, rig apply, and automatic deletion of the untracked shell shim.

## Capabilities

### New Capabilities

- `ghostty-config-assurance`: Defines the canonical Ghostty template behavior, automatic shell-integration ownership, focused source contracts, and isolated rendered validation.

### Modified Capabilities

- `bootstrap`: Adds `check-ghostty` to the non-mutating `just check` validation aggregate and shell-file workflow.

## Impact

- Affected configuration: `rig/home/private_dot_config/ghostty/config.tmpl`, `rig/home/.chezmoidata.toml`, and the zsh parity mirrors.
- Affected validation: new `checks/ghostty.sh`, `justfile`, `.pre-commit-config.yaml`, and the existing shell-file ledger.
- Affected guidance: `rig/home/AGENTS.md` and the terminal, validation, home-config, and shell operator runbooks.
- No new package dependency is introduced. Native parsing is conditional on existing `chezmoi` and `ghostty` binaries; static contracts remain mandatory everywhere.
