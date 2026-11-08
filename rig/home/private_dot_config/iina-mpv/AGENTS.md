# AGENTS

Managed IINA user-defined mpv config (`~/.config/iina-mpv`).

## Rules

- `mpv.conf` stays minimal and must not force a custom shader globally; shader chains are opt-in bindings in `IINA-Native.conf`.
- `shaders-pin.json` is the source/tag/file SHA-256 manifest. Keep Anime4K / FSRCNNX asset names and every keymap shader reference in exact parity (`just check-iina-config`).
- Anime4K and FSRCNNX assets are GPL-3.0. Never vendor `.glsl` files into this repository; `just iina-shaders install --apply` downloads/verifies them into ignored `~/.config/iina-mpv/shaders/`.
- Pin refreshes require current GitHub release evidence, archive/file hash verification, `just iina-shaders doctor`, and docs/OpenSpec updates.
- Operator runbook: `docs/content/docs/iina.mdx`.
