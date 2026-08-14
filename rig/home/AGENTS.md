# AGENTS

## Scope

Chezmoi source tree (`rig/home/`) for `~/.config/*` and `~/.zsh/functions/*`.

Runtime files under `rig/dots/` (`zshrc`, `p10k.zsh`, `gitconfig`, …) are **symlinked** by bootstrap into `$HOME` — not applied by Chezmoi.

## Rules

- `dot_zshrc.tmpl` and `dot_p10k.zsh` are parity mirrors only (`rig/home/.chezmoiignore`)
- `just check-zsh` enforces `cmp` between `rig/dots/*` and mirror files
- Template machine-specific paths (`{{ .chezmoi.homeDir }}` in Ghostty, etc.)
- Keep identities, tokens, auth files, histories, caches, and app DBs out of Git
- Preserve `~/.zshrc.local` and Chezmoi `.local` override patterns
- Nightly backup: `dot_local/bin/executable_kopia-nightly` is the just/repo source. Dest `$HOME/.local/bin/kopia-nightly` is launchd-only and is copied by `just kopia-nightly-install` (`KOPIA_NIGHTLY_REPO`). LaunchAgent template `Library/LaunchAgents/com.wyattowalsh.kopia-nightly.plist.tmpl` (`RunAtLoad=false`, TimeOut 12h). Do not track repository.config or rclone.conf. Operator runbook: `docs/content/docs/backup.mdx`.

## Preview

```bash
just home-diff
just bootstrap --dry-run
```

## Docs sync

Update `docs/content/docs/home-config.mdx` (and `freshen.mdx` / `shell.mdx` when relevant) when layout or deploy paths change.
