# AGENTS

## Scope

`rig/darwin/` — nix-darwin + Home Manager flake for Apple Silicon macOS.

## Rules

- Host `w4w-mbp`, user `ww`, and home `/Users/ww` are **intentional public markers** — not secrets. Host-specific values live in `rig/darwin/hosts/` — not in portable `rig/home/` templates.
- Modules **on disk:** `modules/packages.nix` and `modules/macos-defaults.nix` only. Do not claim shell / services / user module splits as existing.
- Commit `rig/darwin/flake.lock`; apply path requires it (`rig/bootstrap/macos.sh`). Lock may record github inputs as `type: tarball`; bootstrap parses the archive SHA from `locked.url`. Do **not** regenerate the lock in cloud.
- **Package SSOT is `rig/brew/Brewfile`.** `environment.systemPackages` is a tiny bootstrap CLI set (`bash`, `curl`, `git`, `jq`, `ripgrep`).
- No secrets, tokens, or private paths that belong in Chezmoi data
- Validate with `just darwin-check` when `nix` / `darwin-rebuild` are available; lock shape: `just check-darwin-lock`

## Bootstrap integration

```bash
just bootstrap --dry-run             # darwin-rebuild check
just bootstrap --apply               # darwin-rebuild switch --flake ./rig/darwin#w4w-mbp
```

Operator runbook: `docs/content/docs/nix.mdx` / `packages.mdx`.
