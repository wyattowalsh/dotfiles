# AGENTS

## Scope
Nix, nix-darwin, and Home Manager configuration.

## Rules
- Keep host-specific values isolated in host modules.
- Do not encode secrets, tokens, or private paths that belong in Chezmoi data.
- Prefer small modules by concern: packages, shell, macOS defaults, services, and user configuration.
- Validate with `nix flake check` and `darwin-rebuild check` when available.

