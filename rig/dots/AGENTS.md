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
- Oh My Zsh plugins (hard cap ≤12): `git` `gh` `macos` `extract` `sudo` `docker` `aws` `terraform` `uv` `zsh-interactive-cd` `vscode` `brew`
- Atuin owns Ctrl-R (`atuin init zsh --disable-up-arrow --disable-ai` after fzf; `FZF_CTRL_R_COMMAND=`). fzf keeps CTRL-T / ALT-C. Up-arrow stays zsh `HISTFILE`.
- Interactive aliases live in `rig/home/dot_zsh/aliases.zsh` (`~/.zsh/aliases.zsh`); `zshrc` sources that file before `~/.zshrc.local` so local can override. Harness: `opc`/`opa` (OpenCode CLI/app), `cdx`/`cda` (Codex CLI/app), `grk` (Grok Build), `cur`/`curp`/`agt` (Cursor IDE/CLI). Do not alias `oc` (real CLI in agents/bin). `http`/`https` may wrap `xh` only when those names are not already commands. Do not alias `hf` → hyperfine.

## Validation

```bash
just check-zsh
```
