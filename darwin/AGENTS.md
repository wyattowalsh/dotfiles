# AGENTS

## Scope

`darwin/` — nix-darwin + Home Manager flake for Apple Silicon macOS (`w4w-mbp` host).

## Rules

- Host-specific values live in `darwin/hosts/` — not in portable `home/` templates
- Commit `darwin/flake.lock`; apply path requires it (`bootstrap/macos.sh`)
- No secrets, tokens, or private paths that belong in Chezmoi data
- Split modules by concern: packages, shell, macOS defaults, services, user config
- Validate with `just darwin-check` when `nix` / `darwin-rebuild` are available

## Bootstrap integration

```bash
nix flake lock ./darwin          # generate lock before first apply
just bootstrap --dry-run      # darwin-rebuild check
just bootstrap --apply        # darwin-rebuild switch --flake ./darwin#w4w-mbp
```
