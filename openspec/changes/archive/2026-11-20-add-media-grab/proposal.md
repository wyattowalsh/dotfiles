# Add MediaGrab

## Problem

The prior `ytdown` alias encoded a large, destructive, and difficult-to-audit policy while third-party GUIs added unnecessary trust and format-selection layers.

## Decision

Own a thin MediaGrab CLI, launcher, AppleScript source, reproducible SVG icon, settings schema, tests, and docs in the dotfiles SSOT. Chezmoi installs the source and rebuilds a local Desktop app after changes.

## Boundaries

Browser sessions, generated app bundles, logs, settings, raw metadata, and downloaded media remain outside Git. Homebrew continues to own `yt-dlp`, Deno, `ffmpeg-full`, and `resvg`.
