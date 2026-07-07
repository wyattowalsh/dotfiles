# Git Topic

Owns portable Git defaults, aliases, delta pager integration, and conventional-commit helpers.

## Canonical file

`.gitconfig` at repo root — symlinked to `~/.gitconfig` by `bootstrap/macos.sh`.

## Local-only

- Credential helper state and provider OAuth tokens
- User identity overrides if different from tracked defaults (prefer `includeIf` or local config)

## Validation

```bash
git config --global --list   # after bootstrap apply
cmp -s .gitconfig ~/.gitconfig  # when symlinked
```
