# desktop-media-controls Specification

## Purpose

Define the native-first IINA desired state and the safety boundary for retiring the former QoL implementation. The exact-target migration was applied on the live Mac on 2026-09-29; physical IINA 1.5.0-beta2 acceptance remains pending.

## Requirements

### Requirement: Native input profile

The repository SHALL provide `IINA-Native.conf` with direct IINA/mpv bindings for three seek magnitudes, OSD and playlist controls, deliberate image adjustments, pan on both wheel axes when IINA forwards wheel events, and opt-in shader selection. It SHALL NOT bind private F-key bridge actions or represent pointer-anchored zoom as a native capability.

#### Scenario: Seek tiers
- **WHEN** an operator uses Left/a or Right/d unmodified, with Shift, or with Command+Shift
- **THEN** the profile seeks ±10s, ±5s exact, or ±1s exact, respectively

#### Scenario: Wheel acceptance boundary
- **WHEN** the IINA horizontal and vertical scroll preferences are stored as `3`
- **THEN** the runner reports those stored values, but physical forwarding, panning, and modifier pass-through remain pending real IINA 1.5.0-beta2 testing

### Requirement: Direct mpv configuration

The repository SHALL provide a minimal managed `iina-mpv/mpv.conf` without a global shader chain and a pin manifest for optional Anime4K and FSRCNNX assets. The native migration SHALL preserve any separately downloaded shader assets. Shader installation and restore SHALL each require a separately reviewed action.

#### Scenario: Optional assets
- **WHEN** an operator previews or validates shader pins
- **THEN** no download, install, or live IINA configuration change occurs

### Requirement: Exact-target QoL retirement

The repository SHALL NOT deploy the old `IINA-QoL.conf`, custom QoL plugin, or Hammerspoon bridge as desired state. The live migration SHALL require an explicit `--apply`, IINA quit, verified native preference preconditions, positive identity evidence for the exact live QoL bundle, and a complete, separately inspectable backup before it changes any named target. A separately approved `snapshot --apply` SHALL create the reviewable backup without changing live targets; a later, separately approved `apply --backup PATH --apply` SHALL reject omitted or stale reviewed snapshots rather than silently creating or substituting one. The live migration passed its separate snapshot and apply approvals on 2026-09-29; physical beta2 acceptance of the retained native controls remains a separate post-migration gate. It SHALL refuse ambiguous identity, symlinks, dirty or incomplete snapshots, concurrent runner mutations, and uncertain recovery rather than removing a bundle by directory name alone. It SHALL NOT modify sibling plugins, global plugin `.data`/`.preferences`, or downloaded shaders.

#### Scenario: Read-only preflight
- **WHEN** an operator runs preview, doctor, or apply without `--apply`
- **THEN** no target, preference, or backup state is changed and all exact migration targets are disclosed

#### Scenario: Identity unavailable
- **WHEN** the live QoL `Info.json` is a permissions list and any of the five non-private code/UI files fails an independently verified historical-source SHA-256 fingerprint
- **THEN** the live removal lane remains blocked even if its directory is named `IINA-QoL.iinaplugin`

#### Scenario: Separate restore decision
- **WHEN** an apply fails or an operator considers restoring a migration snapshot
- **THEN** the runner exposes the exact backup and rollback path; no later live restore is inferred to be authorized by migration approval

### Requirement: Cursor actions remain deferred

Pointer-anchored zoom, pointer presets, reset and plugin rotation menus SHALL NOT be claimed as native or deployed by this migration. The root `cursor-actions.md` SHALL remain a design-only handoff for a separate decision; absent trustworthy player-space cursor evidence, no center-zoom fallback SHALL be described as cursor zoom.

#### Scenario: Native acceptance
- **WHEN** the operator accepts native playback with real media and hardware in IINA 1.5.0-beta2
- **THEN** acceptance covers only observed native controls; deferred cursor features remain unimplemented

### Requirement: Plugin and private-state boundaries

Only three explicitly pinned official plugin targets MAY be managed by the optional installer; other installed and developer plugins are independent and SHALL be preserved. Plugin preferences, credentials, histories, logs and screenshots SHALL stay outside source control. Per-plugin tuning recommendations SHALL remain blocked without supporting evidence.

#### Scenario: Offline source checks
- **WHEN** `just check-iina-config` and its disposable-root Bats suite run
- **THEN** they validate the native source, target boundaries and safety behavior without mutating a running IINA or Hammerspoon instance
