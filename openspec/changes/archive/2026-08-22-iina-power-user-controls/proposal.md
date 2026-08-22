## Why

The Apple-native IINA power-user profile must live in this rig, not wyattowalsh/agents. Putting the input map, plugin, and Hammerspoon chord bridge in the harness repo would split machine desired-state away from Chezmoi/home.

## What Changes

- Chezmoi: thin Hammerspoon loader + `iina_qol` modules, `IINA-QoL.conf`, unpacked `IINA-QoL.iinaplugin` (code/UI only)
- Homebrew: cask `hammerspoon` beside `iina`
- nix-darwin: only the pinned `com.colliderli.iina` scalars
- `just check-iina-config` + Bats, dedicated IINA operator page on docs sidebar/hub

## Capabilities

### New Capabilities

- `desktop-media-controls`: curated IINA input profile, cursor-at-pointer zoom plugin, and Command+Shift-only Hammerspoon bridge.

### Modified Capabilities

None.

## Impact

- Chezmoi home, Brewfile, nix-darwin defaults, checks, just recipes, docs hub/sidebar, nested `AGENTS.md`
- Agents repo should point here for IINA QoL; it must not keep a second profile SSOT
- Change stays unarchived until live cursor-zoom acceptance

## Non-goals

- WebSocket or IPC router
- Shipping or documenting center-zoom as cursor zoom
- Tracking playback histories, plugin `.data`/`.preferences`, logs, or screenshots
- Broad `chezmoi apply` or `just bootstrap --apply`
- Third-party expanders
- Writing IINA internals databases

## Validation

- `just check-iina-config` and `just check-bats`
- `just docs-ci` and `just secrets-scan`
- Live Mac: disposable-media proof after exact-target export/apply; tap stays off until cursor-at-pointer is proven
