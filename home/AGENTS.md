# AGENTS

## Scope

Chezmoi source tree (`home/`) for `~/.config/*` and `~/.zsh/functions/*`.

Root-level `.zshrc`, `.p10k.zsh`, and `.gitconfig` live at repo root and are **symlinked** by `bootstrap/macos.sh` — not applied by Chezmoi.

## Rules

- `dot_zshrc.tmpl` and `dot_p10k.zsh` are parity mirrors only (`home/.chezmoiignore`)
- `task check:zsh` enforces `cmp` between root and mirror files
- Template machine-specific paths (`{{ .chezmoi.homeDir }}` in Ghostty, etc.)
- Keep identities, tokens, auth files, histories, caches, and app DBs out of Git
- Preserve `~/.zshrc.local` and Chezmoi `.local` override patterns

## Preview

```bash
task home:diff
task bootstrap -- --dry-run
```

## Docs sync

Update `docs/content/docs/home-config.mdx` and `home/README.md` when layout or deploy paths change.