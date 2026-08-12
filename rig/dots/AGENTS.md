# AGENTS

## Scope

Tracked **runtime home files** that bootstrap symlinks into `$HOME` (not Chezmoi-applied).

| Repo path | Home target |
| --- | --- |
| `rig/dots/zshrc` | `~/.zshrc` |
| `rig/dots/p10k.zsh` | `~/.p10k.zsh` |
| `rig/dots/gitconfig` | `~/.gitconfig` |
| `rig/dots/ripgreprc` | `~/.ripgreprc` |
| `rig/dots/editorconfig` | `~/.editorconfig` |

## Rules

- Keep in sync with Chezmoi parity mirrors: `rig/home/dot_zshrc.tmpl`, `rig/home/dot_p10k.zsh` (`just check-zsh` / `cmp`)
- Linked by `rig/bootstrap/macos.sh` and `rig/bootstrap/linux.sh` — not by Chezmoi
- No secrets; machine overrides via `~/.zshrc.local` or untracked includes

## Validation

```bash
just check-zsh
```
