# AGENTS

## Scope

Chezmoi source tree (`rig/home/`) for `~/.config/*`, `~/.zsh/aliases.zsh`, `~/.zsh/functions/*`, and related home templates.

Runtime files under `rig/dots/` (`zshrc`, `p10k.zsh`, `gitconfig`, …) are **symlinked** by bootstrap into `$HOME` — not applied by Chezmoi.

## Rules

- `.chezmoiignore` lists **target** (destination) paths: `.zshrc`, `.p10k.zsh`, `AGENTS.md`, plus IINA runtime (`Library/Application Support/com.colliderli.iina/` plugin `.data`/`.preferences`, `history.plist`, `watch_later`, logs, `screenshots`). Chezmoi matches dest names; source names (`dot_zshrc.tmpl`, `dot_p10k.zsh`) match nothing. Gate: `just check-chezmoi-ignore`.
- On the named MBP/MBA accounts, preserve the legacy music/Navidrome target ignores and install refusal. The existing MBA contract installer owns guarded activation; retained plists are manual rollback state, not a reason to re-enable legacy installation. Home apply does not retire installed files or pass live ownership/recovery proof. Keep MBP backup/workstation tools. Runbook: `docs/content/docs/music.mdx`.
- `dot_zshrc.tmpl` and `dot_p10k.zsh` are parity mirrors only. `just check-zsh` `cmp`s them against `rig/dots/*`.
- Ghostty defaults live in `rig/home/.chezmoidata.toml`. Template `private_dot_config/ghostty/private_config.tmpl` keeps the deployed file mode `0600`, uses `chezmoi:template:missing-key=zero`, and loads the optional sibling-relative overlay `config-file = ?config.local`.
- Template actual machine-specific asset paths with `{{ .chezmoi.homeDir }}` (Ghostty background/sound, etc.); do not use it for sibling config includes.
- Keep identities, tokens, auth files, histories, caches, and app DBs out of Git (including Atuin `history.db`/`key`/`session` and usql DSNs)
- Preserve `~/.zshrc.local` and Chezmoi `.local` override patterns
- XDG tools: `private_dot_config/{atuin,ast-grep,agent-deck,apple-text,xh,lnav,visidata,yazi,direnv,fd,bat,git}/` plus `sgconfig.yml`, `dot_duckdbrc`, `dot_usqlrc` (highlight only). Claude/Codex Atuin hooks live in wyattowalsh/agents. Apple text expansion SSOT is `private_dot_config/apple-text/` plus `just apple-text`; overlay `expansions.local.json` is local-only. Runbook: `docs/content/docs/apple-text.mdx`.
- Nightly backup: source `dot_local/bin/executable_kopia-nightly`. On the named MBA account, Chezmoi withholds its runner and plist, and the runner refuses install and execution. On the MBP, Chezmoi writes `~/.local/bin/kopia-nightly` and `just kopia-nightly-install` can copy the source when `KOPIA_NIGHTLY_REPO` is set. Plist: `Library/LaunchAgents/com.wyattowalsh.kopia-nightly.plist.tmpl` (`RunAtLoad=false`, 04:00 calendar). Keep the wall-clock cap in the runner (`KOPIA_NIGHTLY_TIMEOUT_SEC`, default 43200). Never point checks at live Kopia, launchctl, or Notification Center. Keep `repository.config` and `rclone.conf` untracked. Operator runbook: `docs/content/docs/backup.mdx`.
- IINA native SSOT is `Library/Application Support/com.colliderli.iina/input_conf/IINA-Native.conf` plus `private_dot_config/iina-mpv/`. Custom QoL plugin/Hammerspoon source is retired; only an explicitly reviewed `just iina-native` migration can remove live QoL paths. Sibling plugins, overlays, history, and plugin preferences stay untracked. Runbook: `docs/content/docs/iina.mdx`.

## Preview

```bash
just home-diff
just bootstrap --dry-run
```

## Docs sync

Update `docs/content/docs/home-config.mdx` (and `apple-text.mdx` / `backup.mdx` / `terminal.mdx` / `shell.mdx` when relevant) when layout or deploy paths change.
