@./AGENTS.md

## Gemini-specific notes

- Use **uv** for Python operations in this repo
- Prefer: loguru, tenacity, tqdm, fastapi, typer, sqlmodel, fastmcp
- Bash scripts: `set -euo pipefail`; guard installs with `command -v`
- macOS validation: `just check`, `just ci`
- Docs site: `just docs-build` — runbooks in `docs/content/docs/`