# AGENTS

Chezmoi `~/.zsh/` sources: aliases + autoload functions.

| Repo path | Home target |
| --- | --- |
| `rig/home/dot_zsh/aliases.zsh` | `~/.zsh/aliases.zsh` (sourced from `~/.zshrc`) |
| `rig/home/dot_zsh/functions/` | `~/.zsh/functions/` |

## Rules

- Keep aliases in `aliases.zsh`, not in `rig/dots/zshrc`
- Every `alias name=` needs an immediately preceding `#:` description (`alias-help` / `als`; `just check-zsh` via `checks/zsh-alias-docs.sh`)
- Freeze expansions of existing aliases; append new ones rather than rewriting the catalog
- `http`/`https` aliases wrap `xh` only when those names are not already commands
- Do not alias `hf` → hyperfine (`hf` is Hugging Face)
- `~/.zshrc.local` is sourced after aliases and may override them
- Harness aliases: `opc`/`opa` (OpenCode CLI/app), `cdx`/`cda` (Codex CLI/app), `grk` (Grok Build), `cur`/`curp`/`agt` (Cursor IDE/CLI). Do not alias `oc` — `agents/bin/oc` is a real CLI
- Tool aliases: `bench` (hyperfine), `jcp` (`jc -p`), `mtrc` (mtr report), `atuin-agents`
- Lister is `alias-help` (alias `als`). Do not name it `aliases` (zsh `$aliases` map)
- you-should-use is sourced from zshrc after aliases, not via `plugins=()`
- Function rules: `functions/AGENTS.md`

## Validation

```bash
just check-zsh
just zsh-alias-usage    # local HISTFILE tokens only
```
