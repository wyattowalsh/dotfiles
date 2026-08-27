# Design: freshen live visual overhaul

Date: 2026-08-27
Status: shipped in `freshen` 1.11.0 (zsh painter; no Gum/HTML)

## Locked decisions

| Decision | Choice |
| --- | --- |
| Canvas | Redesign **live + recap in zsh** (not Gum, not HTML, not a new TUI) |
| Language | Dense operator data + Charm-soft chrome (rounded unicode, muted palette) |
| Composition | Hybrid: PHASES rail + NOW pane |
| Builder | Nested zsh painter + golden FORCE_LIVE dumps |
| Success bar | Tests fail if live is still seven `icon Phase: status` lines |
| Alt-screen | Keep: sudo/confirm pause, abort on sudo fail, leave before recap |
| Width | Query `/dev/tty` via `stty` (not `$COLUMNS` alone) |
| OVERALL | Discovery DAG: inventory fans out to formula/cask/app node-waves, then cleanup → caches → doctor |
| Blink | Skip identical frames; home + overwrite + erase-below (never `\\e[H\\e[J` wipe) |
| Bare `freshen` | `-Y -P --dev-prune-root=$HOME/dev -v -D -R=auto`; verbose does not disable live |
| Busy lock | List holder + children; offer replace; never SIGKILL a login shell |

## Live frame (width ≥ 80)

Rounded box with PHASES rail + NOW pane. NOW holds the OVERALL discovery DAG (inventory fans out to per-package formula/cask/app nodes, then cleanup → caches → doctor), a short package list, last brew child lines, elapsed, and Attention.

## Live frame (width < 80)

Stack NOW above PHASES inside the same outer box. Truncate with existing `_truncate`.

## Recap frame

Same outer box after `_live_leave`. Interior order: ATTENTION → NEXT → SUMMARY → Total / Skipped / Log. Honesty tokens unchanged. Dry-run stays unboxed.

## Palette (256-color)

frame 240, title/running 212, done 114, failed 203, dim 244. `NO_COLOR=1` keeps glyphs. `--progress=plain` has no box.

## Painter

Nested `_ui_*` helpers in `freshen`, registered in `_freshen_helper_fns`. No second autoload file.

## Tests

`tests/cases/live_visual.zsh`: PHASES/NOW/╭, anti-old-dump, plain has no chrome, OVERALL + package nodes, wide header, narrow labels.

## Out of scope

Gum, glow recap, HTML, truecolor-only, spinner, restyling honesty tokens, `plain` boxed recap.
