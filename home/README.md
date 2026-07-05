# Home Configuration

Chezmoi source tree for `~/.config/*` and `~/.zsh/functions/*`.

Root-level `.zshrc`, `.p10k.zsh`, and `.gitconfig` live at the repo root and are **symlinked** by `bootstrap/macos.sh`. `dot_zshrc.tmpl` and `dot_p10k.zsh` are parity mirrors only (listed in `home/.chezmoiignore`).

Operator docs: [`docs/content/docs/home-config.mdx`](../docs/content/docs/home-config.mdx)

Tracked today:
- `dot_zshrc.tmpl` / `dot_p10k.zsh` — must stay in sync with repo root copies (`task check:zsh` enforces `cmp`)
- `dot_zsh/functions/` — `freshen`, `sync-cursor`, tests
- `private_dot_config/{ghostty,lazygit,yazi}/` — terminal tooling

Rules:
- Promote from live rig via `task inventory:redacted`, then curate into this tree.
- Machine-specific values use Chezmoi templates (`ghostty` background paths use `{{ .chezmoi.homeDir }}`).
- Ghostty background assets stay local under `~/.config/ghostty/backgrounds/` (not committed).
- Secrets, auth files, histories, telemetry, caches, app databases, and session state stay out of Git.

Preview:

```bash
task home:diff
task bootstrap -- --dry-run
```

