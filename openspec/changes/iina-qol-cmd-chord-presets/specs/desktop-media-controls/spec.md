## RENAMED Requirements

- FROM: `### Requirement: Chord-only cursor zoom`
- TO: `### Requirement: Command-gated cursor zoom`
- FROM: `### Requirement: Tap default off`
- TO: `### Requirement: Tap default on`

## MODIFIED Requirements

### Requirement: Command-gated cursor zoom

The Hammerspoon bridge SHALL consume scroll only while Command is held (Shift optional), scoped to IINA player windows, and SHALL send direction-only private F-keys. Scroll without Command, or with alt/ctrl/fn, SHALL pass through natively. The plugin SHALL read mpv `mouse-pos`/`hover` in player space before changing geometry.

#### Scenario: Command chord zoom

- **WHEN** Command+scroll (with or without Shift) occurs over a visible IINA player
- **THEN** the bridge focuses that window on the first zoom gesture and the plugin zooms at the pointer

#### Scenario: Plain scroll remains native

- **WHEN** unmodified vertical or horizontal scroll occurs over IINA
- **THEN** vertical scroll changes playback speed at IINA's moderate step, horizontal scroll seeks, and the bridge does not consume the gesture

#### Scenario: Other modifiers pass through

- **WHEN** scroll modified by alt, ctrl, or fn occurs over IINA
- **THEN** the bridge does not consume the gesture

#### Scenario: Static chord contract

- **WHEN** `just check-iina-config` inspects Hammerspoon sources
- **THEN** it requires the `isZoomChord` gate and rejects a regressed exact-Command+Shift-only source

### Requirement: Tap default on

Tracked Hammerspoon source SHALL default the scroll tap on. The tap was enabled after live cursor-zoom acceptance and SHALL stay on by default; `disableSession()` stops it for the session only.

#### Scenario: Source default

- **WHEN** `just check-iina-config` inspects Hammerspoon sources
- **THEN** it asserts the tap default is on

### Requirement: Zoom bounds

Zoom SHALL stay between 100% and 1000% with a soft 100% detent and SHALL never shrink below the fitted view. Command+Shift+0 and the plugin reset key SHALL restore 100% zoom, centered pan, and 0° rotation. Newly loaded files SHALL start at 100% centered and unrotated; zoom, pan, and rotation SHALL NOT carry into the next item.

#### Scenario: Reset and file boundary

- **WHEN** the operator resets zoom or loads a new file
- **THEN** the view is 100% zoom, centered, and unrotated

## ADDED Requirements

### Requirement: Zoom presets and rotation

The plugin SHALL provide three configurable zoom presets (default 100 / 200 / 400%), clamped to the zoom bounds, bound to Shift+Command+1/2/3 and exposed in the plugin menu. Preset jumps SHALL anchor at the pointer via the same fail-closed cursor path as scroll zoom. The plugin SHALL cycle `video-rotate` in 90° steps on Command+r with OSD feedback.

#### Scenario: Preset jump

- **WHEN** the operator presses Shift+Command+2 over the player
- **THEN** zoom jumps to preset 2 (200% by default) anchored at the pointer and the OSD shows the zoom percent

#### Scenario: Preset clamps

- **WHEN** a stored preset exceeds the configured maximum (or sits below the minimum)
- **THEN** the jump clamps into the configured bounds

#### Scenario: Rotation cycle

- **WHEN** the operator presses Command+r repeatedly
- **THEN** rotation cycles 0°→90°→180°→270°→0° with an OSD readout

### Requirement: Profile readouts and image adjust

The input profile SHALL provide an OSD time/percent readout (`o`), a media-title readout (`Shift+o`), playlist shuffle (`Ctrl+p`), and deliberate image adjustment on Ctrl+digits (brightness, contrast, gamma, saturation ±5). Plain digits 1–8 SHALL remain ignored.

#### Scenario: Readouts and shuffle

- **WHEN** the operator presses `o`, `Shift+o`, or `Ctrl+p`
- **THEN** the OSD shows position/percent or the media title, or the playlist shuffles

#### Scenario: Image adjust stays deliberate

- **WHEN** the operator presses plain `1`–`8` versus `Ctrl+1`…`Ctrl+8`
- **THEN** plain digits do nothing and Ctrl+digits adjust brightness/contrast/gamma/saturation by ±5

### Requirement: Opt-in pinned upscaling

The profile SHALL offer FSRCNNX quality/fast and Anime4K fast/HQ A/B/C shader chains plus a clear/off binding. No custom shader SHALL be enabled globally. Every referenced shader SHALL appear in a committed source/tag/file SHA-256 manifest; GPL shader assets SHALL be downloaded, verified, installed outside Git, and recoverable from timestamped backups.

#### Scenario: Natural-content upscale

- **WHEN** the operator presses Command+u or Shift+Command+u
- **THEN** the profile applies the pinned FSRCNNX quality or fast shader and reports the selection on the OSD

#### Scenario: Anime modes

- **WHEN** the operator presses Alt+1/2/3 or Shift+Alt+1/2/3
- **THEN** the profile applies pinned Anime4K fast or HQ mode A/B/C chains from the upstream v4 instructions

#### Scenario: Shader reset

- **WHEN** the operator presses Ctrl+u
- **THEN** all custom GLSL shaders are cleared

#### Scenario: Pin or install drift

- **WHEN** `just check-iina-config` or `just iina-shaders doctor` runs
- **THEN** unpinned keymap references, invalid manifests, missing files, and SHA-256 drift fail validation without writing live state

### Requirement: Official plugin release pins

The rig SHALL pin the currently installed official Online Media, OpenSubtitles, and User Scripts plugins to release assets from their `iina/plugin-*` repositories. Install SHALL verify package SHA-256, reject unsafe archive paths, validate the root manifest identifier/version, preserve runtime `.data` / `.preferences`, require IINA to be quit, and create a restore snapshot before replacement.

#### Scenario: Official plugin update

- **WHEN** the operator runs `just iina-plugins install --apply` with IINA quit
- **THEN** the three official plugin directories are replaced by the pinned versions and the prior directories remain recoverable

#### Scenario: Installer remains safe by default

- **WHEN** the operator runs either installer without `--apply`
- **THEN** it prints a dry-run plan and neither downloads nor mutates live state

### Requirement: Managed mpv config and thumbnails

The rig SHALL deploy a minimal user-defined mpv config directory, enable it through IINA's native preferences, and pin timeline thumbnail preview with 480px width, a 1 GiB cache, and mounted-remote-drive generation. It SHALL use AVFoundation audio on this machine because CoreAudio fails channel-layout initialization against the current multi/virtual-device topology. It SHALL disable fullscreen-on-open to avoid IINA 1.5.0-beta1's failed AppKit transition leaving the loaded player window inaccessible; explicit `f` fullscreen remains available. The config SHALL NOT force a shader globally.

#### Scenario: Exact-target apply

- **WHEN** `just iina-qol apply --apply` runs
- **THEN** it deploys `mpv.conf` and the shader manifest, writes the native config/thumbnail preferences, and backs up prior files/defaults

### Requirement: Bookmarks respects IINA plugin contracts

The Bookmarks plugin SHALL enable native overlay hit-testing only while visible, keep related actions under a submenu so it publishes no more than five first-level menu items, declare every active preferences-page/runtime storage key in `Info.json`, parse IINA's native preference value types, and connect each exposed setting to observable behavior. Loading or hiding the overlay SHALL set clickability false; showing it SHALL set clickability true immediately before display. Controls without runtime behavior SHALL not be exposed.

#### Scenario: Bookmarks startup

- **WHEN** IINA loads the enabled Bookmarks plugin while its overlay is hidden
- **THEN** native `PluginOverlayView.hitTest` does not spin and the application reaches a responsive window at idle CPU

#### Scenario: Overlay lifecycle

- **WHEN** the Bookmarks overlay is shown, hidden from the menu, or closed by its UI
- **THEN** clickability is enabled for show and disabled for both hide paths, with regression tests asserting call order

#### Scenario: Menu and preference schema

- **WHEN** IINA loads the Bookmarks plugin
- **THEN** it receives at most four first-level menu items, every active preference key has a type-correct default, native boolean/number values are honored, all three UIs receive validated display/sort snapshots, quick-note prompting is opt-in, and no menu-limit or undefined-key warnings are produced
