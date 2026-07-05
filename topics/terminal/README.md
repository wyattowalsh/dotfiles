# Terminal Topic

Owns terminal emulator config, fonts, and portable visual defaults.

## Canonical files

- `home/private_dot_config/ghostty/config.tmpl` — Ghostty settings with templated asset paths
- Nerd Font casks in `brew/Brewfile` (`font-fira-code-nerd-font`, etc.)

## Local assets

Background images under `~/.config/ghostty/backgrounds/` — not committed. Templates reference `{{ .chezmoi.homeDir }}`.

## Validation

```bash
task home:diff
task brew:check   # font casks
```