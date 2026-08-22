# AGENTS

Unpacked IINA plugin `IINA-QoL.iinaplugin` (code/UI only). Identifier `com.wyattowalsh.iina-qol`.

## Rules

- Runtime entry is `main.js` only. IINA does not load `lib/*`; those files are Node-testable mirrors of zoom math and schema v4 validate/migrate. Do not `require` them from `main.js`.
- Permissions must stay exactly `["show-osd"]`. No network, filesystem, shell, overlay, or alert.
- Keys carry direction only. Cursor zoom reads the current pointer in player space: IINA `input` callback `{x,y}` is documented as the cursor relative to the player window (AppKit origin, flipped into OSD space). Require the point to land in the video rect. Fall back to mpv `mouse-pos` only when `hover === true`. Never invent hover. If that cannot anchor, consume the key and OSD `zoom unavailable`. Never center-zoom. Do not call `menu.forceUpdate` during plugin load (IINA 1.4.4 recursive libdispatch crash).
- Preference writes: settings UI, one-time schema migration, one-time hint (`hintVersion` 0→4). No per-gesture counters or playback history.
- Do not track sibling plugins, `.data`, `.preferences`, logs, histories, or screenshots.
- Operator runbook: `docs/content/docs/iina.mdx`.
