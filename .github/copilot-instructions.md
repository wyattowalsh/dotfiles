@./AGENTS.md

## Repo context

- **Personal public SSOT** for host `w4w-mbp` (user `ww`) — shell, git, brew, nix-darwin, Chezmoi home config
- **AI/MCP harness SSOT:** [wyattowalsh/agents](https://github.com/wyattowalsh/agents) — do not add MCP JSON or client configs here
- **macOS path:** `just bootstrap` → `rig/brew/Brewfile` + `rig/dots` symlinks + Chezmoi + nix-darwin
- **Linux path:** `./setup.sh` → `rig/bootstrap/linux.sh` — apt bootstrap + optional AI CLI/skills install (configs still from agents repo)

## Validation before merge

```bash
just check
just ci
```

## Env vars only

- Document names in `.env.example`; never commit token values
- Run `just secrets-scan` when touching credential-adjacent docs
