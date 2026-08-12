# Dotfiles Bootstrap

Private, personal, internal-only dotfiles SSOT. Curated desired state for shell, git, Homebrew, nix-darwin, and Chezmoi home config. AI/MCP harness configs live in [wyattowalsh/agents](https://github.com/wyattowalsh/agents).

<!-- BADGES:START -->

[![Platform: Debian/Ubuntu](https://img.shields.io/badge/Platform-Debian%2FUbuntu-E95420?style=flat-square&logo=ubuntu&logoColor=white)](#prerequisites)
[![Bootstrap: Bash](https://img.shields.io/badge/Bootstrap-Bash-121011?style=flat-square&logo=gnubash&logoColor=white)](./setup.sh)
[![Setup: Idempotent](https://img.shields.io/badge/Setup-Idempotent-2ea44f?style=flat-square)](#idempotency)
[![License](https://img.shields.io/github/license/wyattowalsh/dotfiles?style=flat-square)](./LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/wyattowalsh/dotfiles?style=flat-square)](https://github.com/wyattowalsh/dotfiles/commits)

<!-- BADGES:END -->

## Entrypoints

| Platform | First command | Docs |
| --- | --- | --- |
| Apple Silicon macOS | `just bootstrap --dry-run` | [Fresh Mac](./docs/content/docs/fresh-mac.mdx) |
| Debian/Ubuntu Linux | `./setup.sh --dry-run --verbose` (→ `rig/bootstrap/linux.sh`) | [Linux setup](./docs/content/docs/linux-setup.mdx) |

## Quick start (macOS)

```bash
git clone <repo-url> ~/dev/projects/dotfiles
cd ~/dev/projects/dotfiles
just bootstrap --dry-run
# review, then:
# nix flake lock ./rig/darwin && just bootstrap --apply
exec zsh -l
just check
```

Machine desired-state lives under [`rig/`](./rig/) (`bootstrap`, `dots`, `brew`, `darwin`, `home`). After layout moves, re-run `just bootstrap --apply` so home symlinks point at `rig/dots/*`.

## Operator documentation

**SSOT for human runbooks:** the Fumadocs site under [`docs/`](./docs/).

```bash
just docs-build    # static site → docs/out
cd docs && pnpm dev
```

Start from [docs index](./docs/content/docs/index.mdx): SSOT workflow, validation matrix, packages, shell, security, AI harness pointers.

## Common just recipes

```bash
just --list
just check
just ci
just inventory-redacted
just brew-check
just secrets-scan
just docs-ci
```

## Prerequisites

<a id="prerequisites"></a>

- **macOS:** Xcode CLT, stable clone path, `rig/darwin/flake.lock` before `--apply`
- **Linux:** `bash`, `git`, `curl`, `apt-get` (or expect apt skips), network

## Idempotency

<a id="idempotency"></a>

Re-running bootstrap/`setup.sh` should converge without duplicate artifacts. See [`AGENTS.md`](./AGENTS.md) for the full contract.

## Security

- Do **not** commit secrets (tokens, API keys, private keys)
- `just secrets-scan` checks tracked files without printing secret values
- Env var **names** only in [`.env.example`](./.env.example)

## License

See [LICENSE](./LICENSE).
