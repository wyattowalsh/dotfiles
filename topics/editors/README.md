# Editors Topic

Owns editor and IDE configuration safe to reproduce across machines.

## Policy

| Track | Examples |
| --- | --- |
| Portable | LSP defaults, extension recommendations, shared settings |
| Local only | Provider auth, extension caches, workspace histories, telemetry |

## Related paths

- `.github/lsp.json` — repo-level LSP for GitHub tooling
- Copilot CLI LSP/MCP — managed in [wyattowalsh/agents](https://github.com/wyattowalsh/agents) or live `~/.copilot` (not tracked here)
- Casks: `cursor`, `visual-studio-code@insiders` in `brew/Brewfile`

## Validation

Promote editor config into `home/` Chezmoi templates when ready; preview with `just home-diff`.