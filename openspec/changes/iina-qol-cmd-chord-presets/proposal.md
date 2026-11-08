## Why

The operator expected Command+scroll to zoom; the shipped bridge demanded Command+Shift. The curated profile also lacks instant time/title readouts, deliberate image adjust, shuffle, zoom presets, and rotation — and the retired pre-plugin "Scroll Zoom" conf, a drifted `verticalScrollAction` default, and a stale "tap default off" spec requirement lingered across live state and docs.

## What Changes

- Hammerspoon chord: consume Command±Shift scroll (Command required, Shift optional; alt/ctrl/fn and unmodified scroll pass through)
- `IINA-QoL.conf`: `o` time/percent OSD, `Shift+o` media title, `Ctrl+p` playlist-shuffle, `Ctrl+1…8` brightness/contrast/gamma/saturation ±5 (plain digits stay ignored hazards)
- Plugin 4.1.0 (settings schema v5): configurable zoom presets (`Shift+Cmd+1/2/3`, default 100/200/400%), `video-rotate` cycle (`Cmd+r`), rotation-aware reset, menu items for presets/rotate
- `iina-qol.sh`: apply prunes the legacy "IINA QoL Scroll Zoom.conf" (backed up first), deploys the tracked mpv config/pin, and pins user-config + thumbnail preferences plus measured IINA 1.5 workarounds (fullscreen-on-open off; AVFoundation audio); doctor reports defaults drift, legacy conf, broken plugin symlinks, and repo-vs-live plugin version
- Pinned enhancement ecosystem: opt-in Anime4K v4.0.1 + FSRCNNX shader profiles and latest official Online Media/OpenSubtitles/User Scripts releases; checksum-enforcing dry-run installers with backup/doctor/restore; no third-party package binaries or GPL shaders committed
- Bookmarks: scope overlay clickability to visible periods so IINA 1.5.0-beta1 no longer loops in `PluginOverlayView.hitTest` / `MenuController.updatePluginMenu` at startup
- Checks: chord, conf, shader-binding/pin, official-plugin pin, plugin feature, schema-v5 and zoom-math contracts; Bats dry-run/prune/chord/shader regression coverage
- Spec sync: corrects the drifted "Tap default off" requirement (shipped reality: tap defaults on)

## Capabilities

### Modified Capabilities

- `desktop-media-controls`: Command-gated chord (renamed from chord-only), tap-default-on correction, zoom presets/rotation, profile readouts/image adjust.

## Impact

- `rig/home` Hammerspoon bridge, QoL plugin/profile, `private_dot_config/iina-mpv`, official-plugin/shader pins; checks/installers/Bats/fixtures; IINA/home-config/validation/nix docs; this capability's spec
- Live Mac via `just iina-qol apply --apply`, `just iina-shaders install --apply`, and `just iina-plugins install --apply`, each reversible from timestamped backups
- Latest official pins at implementation time: Online Media v0.9.10, OpenSubtitles v0.9.6, User Scripts v0.9.3; Anime4K v4.0.1 and FSRCNNX 1.1 release files

## Non-goals

- Consuming unmodified scroll — volume/speed/seek stay native
- Adding redundant `plugin-more-seeking` (the curated profile already owns seeking)
- Persistently forcing a shader chain; shipping downloaded packages/shaders in Git
- New IINA-QoL plugin permissions beyond `show-osd`; any center-zoom fallback; whole-home chezmoi apply

## Validation

- `just check-iina-config`, `just check-bats`, `just check-shell`, `uv run python checks/iina_zoom.py --self-test`
- `just iina-qol preview` then `apply --apply`; live proof (Cmd+scroll zoom, presets, rotate, readouts, F15 self-test) gates archive
