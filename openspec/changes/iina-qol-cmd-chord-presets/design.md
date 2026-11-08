## Context

The bridge consumed only the exact Command+Shift chord; the operator's muscle memory is Command+scroll. The plugin (4.0.2) already had per-gesture OSD zoom readouts, fail-closed cursor anchoring, and a schema migration path, so presets and rotation extend existing machinery rather than adding new subsystems.

## Goals / Non-Goals

**Goals**

- Command+scroll zooms; both chords work; unmodified/alt/ctrl/fn scroll stays native
- Profile gains readouts (`o`, `Shift+o`), shuffle (`Ctrl+p`), deliberate image adjust (`Ctrl+1…8`)
- Plugin 4.1.0: cursor-anchored zoom presets, rotation cycle, rotation-aware reset
- Opt-in, checksum-pinned natural/anime upscaling profiles; latest official IINA plugins
- User mpv config + high-quality/remote thumbnail defaults managed without tracking runtime assets
- Bookmarks overlay hit-testing enabled only while visible
- Retired scroll-zoom conf pruned from live state with backup; doctor surfaces drift

**Non-goals**

- Plain-scroll zoom, sibling-plugin management, new permissions, center-zoom fallback

## Decisions

1. **Command required, Shift optional.** `isZoomChord` drops the Shift term but keeps the alt/ctrl/fn veto and nil guard. Consumption stays scoped to `playerUnderPointer()`, so Safari/Chrome Cmd+scroll outside IINA is untouched, and IINA never sees consumed events.
2. **Presets and rotation live in the plugin, not the conf.** They need OSD feedback and menu entries, which `input.conf` cannot express. A preset is a target log2 instead of a delta; it reuses the same fail-closed `resolveAnchor` → `alignAfterZoom` path; preset 100 routes to `resetView`.
3. **Rotation is orthogonal geometry.** `video-rotate` needs no cursor anchor; `resetView` clears it so `Shift+Cmd+0` and reset-on-file also un-rotate. Cycle 0→90→180→270→0 via `safeGetNumber`/`safeSet`.
4. **Schema v5.** `zoomPreset1/2/3` ints clamped 100–1000; `migrateLegacy` copies them so re-migration is lossless; the `hintVersion` gate re-shows the updated one-time hint (intended).
5. **Apply-side prune with backup.** The legacy "IINA QoL Scroll Zoom.conf" is live-only (untracked); `apply --apply` backs it up under the timestamped state dir then removes it; `restore` already covers the `iina/*` backup path.
6. **Spec drift fix.** The capability still said "tap default off" although the shipped source and checks enforce ON after live acceptance; this change MODIFIES/renames the requirement to match reality.
7. **Image adjust on Ctrl+digits** keeps plain 1–8 ignored (hazard block) — deliberate control requires the modifier. `o`/`Shift+o`/`Ctrl+p` use mpv `show-text` property expansion and `playlist-shuffle`.
8. **Shader chains are opt-in and pinned.** `Cmd+u` / `Shift+Cmd+u` select FSRCNNX quality/fast; `Alt+1/2/3` and `Shift+Alt+1/2/3` select Anime4K fast/HQ A/B/C; `Ctrl+u` clears the list. The installer downloads GPL-3.0 releases, verifies archive + file hashes, and never vendors them.
9. **Official plugins are release-pinned, not vendored.** Only `iina/plugin-*` release assets for the three already-installed official plugins; archive paths, SHA-256, root manifest identifier/version, and destination names are checked before atomic directory replacement. Runtime `.data` / `.preferences` remain siblings and untouched.
10. **Bookmarks clickability follows visibility.** Hidden overlays call `setClickable(false)`; showing sets true immediately before `show()`, and both menu hide and `HIDE_OVERLAY` disable it after hiding. This removes the confirmed IINA 1.5 beta startup loop without removing overlay interaction.
11. **Native preference defaults.** Enable the tracked user config directory, 480px thumbnails, 1 GiB cache, mounted-remote-drive thumbnails, and AVFoundation audio. AVFoundation is a measured machine-specific workaround: CoreAudio fails channel-layout initialization with the current multi/virtual-device topology, while AVFoundation initializes the same test stream cleanly. Pin `fullScreenWhenOpen=false`: IINA 1.5.0-beta1 logs a failed AppKit fullscreen transition and can leave the loaded player window inaccessible; `f` remains the explicit fullscreen control. The Nix path derives from the primary user's home; remote thumbnails remain operator-disableable on slow mounts.
12. **Simplify at existing boundaries.** Bookmarks shares sort/view/display constants, resolves chapter/subtitle enrichment once per add, serializes one snapshot for primary + automatic backup, and sends only the shared single-sort fallback to IINA preferences; per-view rich filter/multi-sort state stays in webview `localStorage`. IINA-QoL commits incremental and preset zoom through one fail-closed target path.
13. **Avoid premature installer/schema frameworks.** The shader and official-plugin installers remain separate because their staging/validation models differ (archive extraction vs package-manifest replacement). Runtime plugin settings and Node-test mirrors remain explicit because IINA cannot import `lib/*`; larger code generation is deferred until there is a second consumer.

## Risks / Trade-offs

- Cmd+scroll is a common app chord; the tap is scoped to IINA windows only, so other apps are unaffected.
- `${time-pos:%H:%M:%S}` strftime expansion must be proven on IINA 1.5.0-beta1's mpv; fallback is plain `${time-pos}` (live gate before archive).
- `video-rotate` and eq properties must respond on the live renderer; drop `Ctrl+1…8` from the profile if they no-op (live gate before archive).
- IINA 1.5.0-beta1 may have fixed the 1.4.4 libdispatch crash; the deferred menu install stays (harmless either way) and the F15 self-test re-proves the bridge.
- Anime4K HQ can miss frame deadlines on demanding 4K sources; profiles are opt-in and have fast/off fallbacks with stats-page verification.
- Official plugin packages execute third-party code; install requires explicit user approval, pins upstream release hashes, and keeps one-step restore snapshots.
