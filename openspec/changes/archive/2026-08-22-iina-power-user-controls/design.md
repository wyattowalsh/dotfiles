## Context

IINA on this Mac needs a curated power-user map plus cursor-at-pointer zoom. Tracked sources replace the live Hammerspoon/plugin stack that currently swallows plain and Command-only scroll.

## Goals / Non-Goals

**Goals**

- Exact Command+Shift chord → direction-only F-keys (F17–F20 zoom, F16 reset, F15 doctor)
- Plugin anchors zoom from mpv `mouse-pos`/`hover` in player space
- Source defaults the Hammerspoon tap off; fail closed if cursor cannot be proven
- Plugin schema v4; exact-target apply with timestamped backups

**Non-goals**

- WebSocket/IPC
- Center-zoom labeled as cursor zoom
- Managing sibling plugins, histories, or screenshot dumps
- Whole-home chezmoi apply

## Decisions

1. **Dotfiles owns the profile.** Agents may name IINA; they must not keep a second plugin/conf SSOT.
2. **Chord-only consume.** Hammerspoon never eats unmodified or Command-only scroll.
3. **Fail closed.** Missing hover/`mouse-pos` does not fall back to center-zoom; the tap stays off.
4. **Schema v4.** Zoom 100–1000%, detent, invert, OSD, reset-on-file, MKV preroll off, `show-osd` only.
5. **Exact-target apply.** Copy/link this change's destinations only; stop if live `init.lua` gained unrelated content.

## Risks / Trade-offs

- Synthetic F-keys carry no cursor location; proof is empirical on the installed IINA/mpv.
- Dirty Hammerspoon `init.lua` at apply time is a hard stop, not an auto-merge.
