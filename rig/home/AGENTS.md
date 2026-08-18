# AGENTS

## Scope

Chezmoi source tree (`rig/home/`) for `~/.config/*`, `~/.zsh/functions/*`, and related home templates.

Runtime files under `rig/dots/` (`zshrc`, `p10k.zsh`, `gitconfig`, …) are **symlinked** by bootstrap into `$HOME` — not applied by Chezmoi.

## Rules

- `.chezmoiignore` lists **target** (destination) paths: `.zshrc`, `.p10k.zsh`, `AGENTS.md`. Chezmoi matches dest names; source names (`dot_zshrc.tmpl`, `dot_p10k.zsh`) match nothing. Gate: `just check-chezmoi-ignore`.
- `dot_zshrc.tmpl` and `dot_p10k.zsh` are parity mirrors only. `just check-zsh` `cmp`s them against `rig/dots/*`.
- Ghostty defaults live in `rig/home/.chezmoidata.toml`. Template `private_dot_config/ghostty/config.tmpl` uses `chezmoi:template:missing-key=zero` and optional `config-file = ?…/.config/ghostty/config.local`.
- Keep identities, tokens, auth files, histories, caches, and app DBs out of Git.
- Preserve `~/.zshrc.local` and Chezmoi `.local` override patterns.
- Nightly backup: source `dot_local/bin/executable_kopia-nightly`. Dest `~/.local/bin/kopia-nightly` is written by Chezmoi apply **and** copied by `just kopia-nightly-install` (`/bin/cp -f` when `KOPIA_NIGHTLY_REPO` is set). Plist: `Library/LaunchAgents/com.wyattowalsh.kopia-nightly.plist.tmpl` (`RunAtLoad=false`, 04:00 calendar). Wall-clock cap is in the **runner** (`KOPIA_NIGHTLY_TIMEOUT_SEC`, default 43200). Do **not** set launchd `TimeOut` (unimplemented) or claim launchd SIGTERM after 12h. Do not track `repository.config` or `rclone.conf`. Operator runbook: `docs/content/docs/backup.mdx`.

## Preview

```bash
just home-diff
just bootstrap --dry-run
```

## Docs sync

Update `docs/content/docs/home-config.mdx` (and `backup.mdx` / `terminal.mdx` / `shell.mdx` when relevant) when layout or deploy paths change.
