# AGENTS

Hammerspoon IINA QoL bridge. Chezmoi source: `rig/home/dot_hammerspoon/` → `~/.hammerspoon/`.

## Rules

- Bundle ID is only `com.colliderli.iina`.
- `DEFAULT_TAP_ENABLED` is `true` after live cursor-zoom acceptance. `start()` binds URL/doctor and starts the exact Command+Shift scroll tap. `disableSession()` stops it for the session.
- Consume **exact** Command+Shift scroll only. Unmodified and Command-only scroll must pass through. Never send volume keys.
- Focus/raise the IINA window under the pointer on the first zoom gesture; ordinary scroll never changes focus.
- Gesture state is in-memory (latch/coalesce). No per-event disk or preference writes. Doctor may print on-demand status.
- Do not deploy this file (repo contract only).
- Operator runbook: `docs/content/docs/iina.mdx`.
