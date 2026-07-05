# Shell Topic

Owns Zsh runtime behavior, PATH ordering, completions, Powerlevel10k prompt, and private overrides.

## Canonical files

| File | Role |
| --- | --- |
| `.zshrc` | Main shell config (repo root, symlinked) |
| `.p10k.zsh` | Powerlevel10k prompt |
| `home/dot_zshrc.tmpl` | Chezmoi parity mirror |
| `home/dot_zsh/functions/` | `freshen`, `sync-cursor`, tests |

## Overrides

- `~/.zshrc.local` — sourced last; machine-specific aliases and env
- Inventory: `task inventory:redacted` → `local/zsh-inventory.txt`

## Validation

```bash
task check:zsh
zsh -n .zshrc
```