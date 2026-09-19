## Why

Interactive zsh startup was blocked by a `compinit` insecure-directory prompt because Homebrew's completion parent was group-writable and third-party installers had appended extra `compinit` calls after Oh My Zsh. The shell configuration also needed durable completion-security guardrails, cleaner cache placement, and measured quality-of-life improvements without replacing the existing Oh My Zsh + Powerlevel10k architecture.

## What Changes

- Restore Model A completion ownership: assemble all completion paths before Oh My Zsh and allow Oh My Zsh to run the only `compinit`.
- Fold Grok and CCS PATH/completion entries into the managed zshrc sections; remove installer-appended initialization drift.
- Remove `ZSH_DISABLE_COMPFIX`, move `ZSH_COMPDUMP` under the XDG cache, and clean obsolete home-directory dumps.
- Normalize `compaudit`-reported completion directories during macOS bootstrap by removing group/world write bits, then verify the result.
- Add a Darwin-only read-only `compaudit` gate and extend structural fixtures so duplicate `compinit`, plugin order, cache placement, and source ordering cannot regress.
- Add `colored-man-pages` and Homebrew `zsh-history-substring-search`, with Up/Down bindings and the upstream-required load order after syntax highlighting.
- Add a report-only, TTY-aware startup timing recipe.
- Evaluate carapace, fzf-tab, Antidote, and Starship without replacing the current prompt/plugin architecture; record measured adopt/defer guidance.

## Capabilities

### New Capabilities

- `zsh-completion-security`: Secure, single-owner zsh completion initialization, bootstrap remediation, XDG cache placement, and regression validation.
- `zsh-runtime-quality`: Curated shell UX additions, stable plugin/source ordering, completion integration, and TTY-aware startup measurement.

### Modified Capabilities

None.

## Impact

Affected surfaces include the canonical and mirrored zshrc files, Homebrew package intent, macOS bootstrap behavior, zsh structure/behavior checks and fixtures, the tracked pnpm completion, Just recipes, and shell/bootstrap/package/validation documentation. Local machine state is also repaired by securing `/opt/homebrew/share`, installing the selected Homebrew plugin, and removing obsolete `~/.zcompdump*` files. No prompt framework or plugin manager migration is included.
