# Repository Instructions

- Keep changes minimal and focused; avoid unrelated refactors.
- Preserve idempotency in bootstrap flows: re-runs must stay safe and must not duplicate config lines or artifacts.
- Never commit secrets (tokens, keys, passwords); use environment variables or untracked local files.
- Use `uv` for Python workflows and `npm` for JavaScript/TypeScript workflows.
- Validate changes with relevant existing checks before finishing.
