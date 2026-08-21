# Full Rig Modernization

## Why
The current repo is a compact Linux-oriented bootstrap. The live machine is a macOS full-rig environment with Homebrew, AI clients, MCPHub, terminal/editor configs, and local state that should be reproducible without committing secrets or volatile runtime data.

## What Changes
- Add a justfile-driven command surface.
- Add macOS bootstrap, Brew, nix-darwin, Chezmoi, and docs scaffolds (AI harness in wyattowalsh/agents).
- Preserve the existing Debian/Ubuntu `setup.sh` path.
- Add nested agent instructions so future agents can edit safely by subsystem.
- Add an internal Fumadocs site for runbooks, inventories, decision records, and validation docs.

## Impact
- Public repo structure changes substantially.
- Bootstrap entrypoints become `just bootstrap` for orchestration and `setup.sh` for the Linux compatibility path.
- AI/MCP harness remains in wyattowalsh/agents; dotfiles documents env var names only.
