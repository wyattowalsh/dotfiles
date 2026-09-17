## 1. Goldens (RED)

- [x] 1.1 Add `tests/cases/live_visual.zsh` (PHASES/NOW/╭, anti-old-dump, plain has no chrome)
- [x] 1.2 Confirm existing live_hygiene / confirm_live / plain tests still named

## 2. Painter

- [x] 2.1 Nested `_ui_*` helpers + registry
- [x] 2.2 `_render_dashboard` paints the two-pane frame (wide)
- [x] 2.3 Narrow width stacks NOW above PHASES
- [x] 2.4 NOW fields: lane, optional package, discovery DAG, brew tail, elapsed, Attention

## 3. Recap

- [x] 3.1 Wrap Attention/Next/Summary in the same outer box after `_live_leave`
- [x] 3.2 Dry-run stays unboxed

## 4. Contracts

- [x] 4.1 `plain` / LOW_POWER / `--no-color` unchanged
- [x] 4.2 sudo/confirm pause and abort unchanged
- [x] 4.3 Honesty tokens unchanged

## 5. Docs

- [x] 5.1 `docs/content/docs/freshen.mdx` describes the dashboard (not seven lines)
- [x] 5.2 `AGENTS.md` visual contract + golden tests
- [x] 5.3 `just check-freshen` + `just docs-ci` if MDX changed
