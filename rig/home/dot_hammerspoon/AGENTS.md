# AGENTS

Hammerspoon IINA QoL bridge. Chezmoi source: `rig/home/dot_hammerspoon/` → `~/.hammerspoon/`.

## Rules

- Bundle ID is only `com.colliderli.iina`.
- `DEFAULT_TAP_ENABLED` is `true` after live cursor-zoom acceptance. `start()` binds URL/doctor and starts the Command+scroll (Shift optional) zoom tap. `disableSession()` stops it for the session.
- Consume **Command±Shift** scroll as cursor zoom (Command required, Shift optional; alt/ctrl/fn fail). Unmodified scroll over an IINA player **pans** (Alt+Meta arrows; no middle-click poke). Never send volume keys. Speed stays on `[` `]` in the input profile, not the wheel. Merge `event:getFlags()` with `hs.eventtap.checkKeyboardModifiers()` — trackpad scroll NSEvents often omit `cmd`. Locate the player via ordered windows, then `application:allWindows()`, then the focused IINA window. Before each private zoom key, post a middle-mouse poke at the pointer so IINA delivers a real window point (`otherMouseUp`). Pin IINA `middleClickAction` to **none (0)** — value 4 is togglePIP and turns Cmd+scroll into Picture-in-Picture. Do not treat synthetic F-key `locationInWindow` as the cursor.
- Focus/raise the IINA window under the pointer on the first zoom gesture; ordinary scroll never changes focus.
- Gesture state is in-memory (latch/coalesce). No per-event disk or preference writes. Doctor may print on-demand status.
- Do not deploy this file (repo contract only).
- Operator runbook: `docs/content/docs/iina.mdx`.
