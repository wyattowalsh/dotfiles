## 1. Chord

- [x] 1.1 `isZoomChord` (Command required, Shift optional) in `iina_qol.lua`; `zoomChord` sample field in `gesture.lua`
- [x] 1.2 Hammerspoon `AGENTS.md` rule; check needles (`isZoomChord`, "shift optional"); Bats chord-regression test; fixture strings
- [x] 1.3 Docs gesture/rule rows updated

## 2. Profile

- [x] 2.1 `o` / `Shift+o` readouts, `Ctrl+p` shuffle, `Ctrl+1…8` image adjust in `IINA-QoL.conf`
- [x] 2.2 Conf needles `show-text` / `playlist-shuffle`; fixture conf synced

## 3. Plugin 4.1.0

- [x] 3.1 Settings schema v5 + `zoomPreset1/2/3` defaults/specs/migration (`main.js`, `lib/settings.js`, `Info.json`)
- [x] 3.2 `applyZoomPreset` (cursor-anchored, fail-closed), `rotateStep`, rotation-aware `resetView`
- [x] 3.3 Bindings `Shift+Meta+1/2/3` and `Meta+r`; menu items; preferences/help pages
- [x] 3.4 Node settings-v5 smoke, `iina_zoom.py` preset cases, plugin feature needles, fixture sync

## 4. Hygiene / tooling

- [x] 4.1 `iina-qol.sh` apply prunes legacy conf (backup-first); restore path already covers the backup
- [x] 4.2 Doctor: defaults drift, legacy-conf warning, broken plugin symlinks, repo/live plugin version diff
- [x] 4.3 Spec deltas: chord rename, tap-default-on correction, presets/rotation, readouts/image adjust
- [x] 4.4 Bookmarks IINA 1.5/settings regressions: fixed hidden-overlay hit-testing (~139% CPU), grouped menus, completed preference schema/native parsing, wired display/sort/enrichment/scratchpad/opt-in quick-note settings, removed no-op controls, and deduplicated enrichment/persistence work. 369 tests, lint, format, typecheck, production build, docs build, and clean live logs pass.
- [x] 4.5 Pin latest official Online Media v0.9.10, OpenSubtitles v0.9.6, User Scripts v0.9.3 release packages with hashes + dry-run installer/doctor/restore; `plugin-more-seeking` omitted as redundant
- [x] 4.6 Pin Anime4K v4.0.1 + FSRCNNX 1.1 shader files and opt-in fast/HQ/off keymap profiles; checksum installer/doctor/restore; downloaded assets ignored
- [x] 4.7 Manage minimal `~/.config/iina-mpv`, user-config preference, remote thumbnails, 480px width, 1 GiB cache, fullscreen-on-open off, and AVFoundation audio; mirror defaults in nix-darwin. Live logs prove the fullscreen/AppKit and CoreAudio/channel-layout failures and their replacements.

## 5. Live apply + proof (gates archive)

- [x] 5.1 `just iina-qol apply --apply`; Hammerspoon private F15 self-test passes on IINA 1.5.0-beta1; pinned defaults in sync (includes `middleClickAction` 0 / none so the zoom poke cannot togglePIP)
- [ ] 5.2 Physical Cmd+scroll and Cmd+Shift+scroll at-pointer behavior (synthetic scroll events do not carry real hardware gesture fields); static chord contract + private F17 pointer-poke zoom pass
- [x] 5.3 `o` / `Shift+o` / `Ctrl+p` and `Ctrl+1` verified in live logs; time property expansion accepted
- [ ] 5.4 Physical `Shift+Cmd+2` preset and `Shift+Cmd+0` visual reset check; `Cmd+r` rotation, reset rotation, doctor health, and no plugin warnings are proven in live logs
- [x] 5.5 Explicitly approved and installed: 14 pinned shaders + official plugins v0.9.10/v0.9.6/v0.9.3; both doctors pass; responsive media relaunch; FSRCNNX set/compile/clear, readouts, shuffle, image adjust, rotation, F17 zoom, and F15 self-test proven in the live mpv/IINA logs. Physical Cmd+scroll + Anime4K mode selection remain human visual checks (synthetic modifier events do not reproduce hardware gesture/key semantics reliably).
