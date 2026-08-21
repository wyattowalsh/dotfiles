## Why

The ecosystem refresh introduced useful shell, Git, Yazi, package, macOS, and research-workflow changes, but review found unsafe PID handling, unresolved package locks, approval-scope drift, documentation drift, and a stale workflow that could claim read-only exhaustive research without proving it. Close those gaps before treating the refresh as assured or using its recommendations for further integration.

## What Changes

- Harden `fkill`, pnpm completion, Oh My Zsh loading, and direnv/uv activation behavior
- Lock Yazi plugins and light/dark flavors while preserving built-in navigation keys
- Make tmux ownership explicit, notebook diff support, approved macOS defaults, and Git integration match the accepted recommendation set
- Add focused regression checks and update every affected operator runbook
- **BREAKING**: retire the dotfiles-owned `rig-ecosystem-refresh` Rhai workflow after its recognized copies are recoverably migrated; the agents repository becomes the skill/workflow SSOT
- Define the cross-repository handoff contract for a dynamic, read-only-before-approval, resumable ecosystem index

## Capabilities

### New Capabilities

- `shell-home-assurance`: Safe shell helpers, reproducible completion, explicit uv synchronization, and locked Yazi configuration.
- `curated-rig-state`: Enforced package, Git, and macOS state that matches the approved refresh rather than later scope drift.
- `ecosystem-research-handoff`: Safe retirement of the local workflow and a fail-closed contract for the external agents-owned research capability.

### Modified Capabilities

None. The repository has no archived baseline capabilities for these reviewed refresh surfaces.

## Impact

- Shell configuration and Chezmoi mirrors, helper functions, completions, and direnv library
- Yazi configuration, package/flavor locks, and key bindings
- Homebrew desired state/exclusions, Git configuration/attributes, and nix-darwin defaults
- Focused checks and operator documentation
- Dotfiles `.grok/workflows` retirement and a coordinated handoff to `wyattowalsh/agents`

No live Homebrew install, Chezmoi apply, nix-darwin rebuild, workflow research run, commit, or push is part of the source change.
