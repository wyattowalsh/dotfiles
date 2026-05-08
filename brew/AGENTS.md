# AGENTS

## Scope
Homebrew taps, formulae, casks, fonts, QuickLook plugins, and services.

## Rules
- Curate the Brewfile; do not blindly treat raw `brew bundle dump` output as desired state.
- Group entries by intent and document service desired state.
- Keep stopped databases and cloud services stopped unless explicitly promoted.
- Validate with `brew bundle check --file brew/Brewfile` when Homebrew is available.

