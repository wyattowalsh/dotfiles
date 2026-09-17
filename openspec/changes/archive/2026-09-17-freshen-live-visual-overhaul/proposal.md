## Why

`freshen --progress=live` still paints seven `icon Phase: status — detail` lines. Operators asked for a major visual overhaul; the last 1.10.0 work repaired alt-screen/sudo/confirm and recap *order*, not chrome. The board must look like a dashboard at a glance, while staying a zsh autoload (sudo, `q`, Ctrl-C, `plain`).

## What Changes

- Live frame: rounded box, PHASES rail + NOW pane (current lane, package, bar, last child line, elapsed, live Attention)
- Recap reuses the same outer box (ATTENTION / NEXT / SUMMARY); honesty tokens unchanged
- 256-color Charm-soft palette; `NO_COLOR` keeps boxes; `plain` stays an unboxed dump
- Width < 80 stacks NOW above PHASES
- Golden FORCE_LIVE dumps: must include pane labels; must not match the old seven-row dump
- No Gum, glow, HTML, or new language

## Capabilities

### Modified Capabilities

- `freshen`: live TTY dashboard and recap chrome (visual contract only; progress modes, honesty, sudo pause unchanged in intent)

## Impact

- `rig/home/dot_zsh/functions/freshen` (painter helpers + recap)
- `rig/home/dot_zsh/functions/AGENTS.md`
- `docs/content/docs/freshen.mdx`
- `rig/home/dot_zsh/functions/tests/cases/live_hygiene.zsh` (+ new golden-frame pack)

## Non-goals

- Gum / Bubble Tea / Textual / HTML popup
- Restyling honesty words (`attempted` / `confirmed` / `unresolved` / `degraded` / …)
- Spinner animation or truecolor-only paint
- Changing `plain --no-color` copy locked by existing tests
- Package-list of every outdated cask on one screen

## Validation

- `just check-freshen`
- New FORCE_LIVE golden tests (structure + anti-old-dump)
- `just docs-ci` if the runbook describes the board
