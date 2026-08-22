## 1. Registries / sources

- [x] 1.1 Chezmoi Hammerspoon loader + `iina_qol` modules
- [x] 1.2 `IINA-QoL.conf` under IINA `input_conf`
- [x] 1.3 Brewfile `cask "hammerspoon"` beside `iina`; nix-darwin pinned IINA scalars only
- [x] 1.4 Chezmoiignore for plugin `.data` / `.preferences` / logs / histories / screenshots

## 2. Plugin

- [x] 2.1 Unpacked `IINA-QoL.iinaplugin` (code/UI only), schema v4, `show-osd` only
- [x] 2.2 Cursor-anchor math from mpv `mouse-pos`/`hover`; fail closed (no center-zoom)
- [x] 2.3 F15 doctor, F16 reset, F17–F20 zoom; Command+Shift +/- / 0; Option+Command pan

## 3. Hammerspoon

- [x] 3.1 Exact Command+Shift chord only; direction-only F-keys; async latched gesture
- [x] 3.2 Hover-focus on first zoom; never consume plain or Command-only scroll
- [x] 3.3 Tap default off until live acceptance

## 4. Checks / docs

- [x] 4.1 `just check-iina-config` + Bats (profile, schema, Lua syntax, chezmoiignore)
- [x] 4.2 Dedicated IINA operator page on docs sidebar and hub
- [x] 4.3 Nested `AGENTS.md` rule-focused; no home-path literals or preference dumps

## 5. Live apply

- [x] 5.1 Exact-target copy/link with timestamped backups; no whole-home chezmoi apply
- [x] 5.2 Disposable-media proof: pointer zoom, 10/5/1 seeks, s/S/Control+s, l/L, plain scroll still speed/seek, hover-focus, per-file reset, doctor
- [x] 5.3 Enable tap only after proof; fail-closed restore if the gate fails
