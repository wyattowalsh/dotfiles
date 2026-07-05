# AGENTS

## Scope

GitHub Copilot instructions, path-specific `.github/instructions/`, LSP config, and CI workflows.

## Files

| Path | Audience |
| --- | --- |
| `copilot-instructions.md` | Repo-wide Copilot (delegates to root `AGENTS.md`) |
| `instructions/*.instructions.md` | Path-scoped guidance via `applyTo` frontmatter |
| `workflows/ci.yml` | Runs `task ci` on push/PR |
| `lsp.json` | Repo-level LSP for GitHub tooling |

## Rules

- Keep Copilot instructions aligned with root `AGENTS.md` — no conflicting policy
- Path instructions stay short; link to subsystem `AGENTS.md` for depth
- Workflows are read-only validation unless explicitly approved to mutate external state
- Update `instructions/docs.instructions.md` when Fumadocs content graph changes

## CI

```yaml
# .github/workflows/ci.yml → task ci
# check + smoke + ai:check + docs:ci
```