# desktop-media-controls Specification

## Purpose
TBD - created by archiving change iina-power-user-controls. Update Purpose after archive.
## Requirements
### Requirement: Chord-only cursor zoom
The Hammerspoon bridge SHALL consume only the exact Command+Shift scroll chord, scoped to IINA player windows, and SHALL send direction-only private F-keys. The plugin SHALL read mpv `mouse-pos`/`hover` in player space before changing geometry.

#### Scenario: Chord zoom
- **WHEN** Command+Shift+scroll occurs over a visible IINA player
- **THEN** the bridge focuses that window on the first zoom gesture and the plugin zooms at the pointer

#### Scenario: Plain scroll remains native
- **WHEN** unmodified vertical or horizontal scroll occurs over IINA
- **THEN** vertical scroll changes playback speed at IINA's moderate step, horizontal scroll seeks, and the bridge does not consume the gesture

### Requirement: Seek tiers
The `IINA-QoL` input profile SHALL bind Left/a to -10s and Right/d to +10s. Shift on either pair SHALL seek ±5s exact. Command+Shift on either pair SHALL seek ±1s exact.

#### Scenario: Three seek magnitudes
- **WHEN** an operator uses arrows or a/d with no modifier, Shift, or Command+Shift
- **THEN** seeks are ±10s, ±5s exact, and ±1s exact respectively

### Requirement: Zoom bounds
Zoom SHALL stay between 100% and 1000% with a soft 100% detent and SHALL never shrink below the fitted view. Command+Shift+0 and the plugin reset key SHALL restore 100% zoom and centered pan. Newly loaded files SHALL start at 100% centered; zoom and pan SHALL NOT carry into the next item.

#### Scenario: Reset and file boundary
- **WHEN** the operator resets zoom or loads a new file
- **THEN** the view is 100% zoom and centered

### Requirement: No center-zoom fallback
The plugin SHALL fail closed when hover/`mouse-pos` cannot anchor. Center-zoom SHALL never be shipped or documented as cursor zoom.

#### Scenario: Unproven cursor
- **WHEN** cursor-at-pointer cannot be proven on the installed IINA/mpv
- **THEN** the live tap stays off and the profile does not fall back to center-zoom

### Requirement: Tap default off
Tracked Hammerspoon source SHALL default the scroll tap off. One serialized edit MAY enable it only after live cursor-zoom acceptance.

#### Scenario: Source default
- **WHEN** `just check-iina-config` inspects Hammerspoon sources
- **THEN** it asserts the tap default is off

### Requirement: Plugin show-osd only
The plugin SHALL request only `show-osd`. It SHALL NOT request network, filesystem, shell, overlay, or alert permission.

#### Scenario: Permission surface
- **WHEN** `just check-iina-config` validates plugin schema
- **THEN** declared permissions are `show-osd` only

### Requirement: No history tracking
Chezmoi SHALL track the unpacked plugin code/UI, `IINA-QoL.conf`, and Hammerspoon modules only. It SHALL NOT track sibling plugins, `.data`, `.preferences`, logs, histories, or screenshots.

#### Scenario: Tracked plugin surface
- **WHEN** chezmoiignore and source layout are validated
- **THEN** history and preference dumps are excluded from desired-state

### Requirement: Checks never mutate live apps
`just check-iina-config` and its Bats suite SHALL validate the input profile, plugin schema, Hammerspoon syntax, and chezmoiignore targets without writing live IINA or Hammerspoon state.

#### Scenario: Offline check
- **WHEN** CI or an operator runs `just check-iina-config`
- **THEN** the command does not mutate running IINA or Hammerspoon configuration
