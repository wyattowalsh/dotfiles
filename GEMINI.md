@./AGENTS.md

## Gemini-specific notes

- Use **uv** for Python operations in this repo
- Prefer: loguru, tenacity, tqdm, fastapi, typer, sqlmodel, fastmcp
- Bash scripts: `set -euo pipefail`; guard installs with `command -v`
- macOS validation: `task check`, `task ci`
- Docs site: `task docs:build` — runbooks in `docs/content/docs/`