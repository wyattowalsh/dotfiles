## Context

Ghostty is installed as the stable Homebrew cask and its canonical configuration is rendered from `rig/home/private_dot_config/ghostty/config.tmpl` using public defaults in `rig/home/.chezmoidata.toml`. The tracked config already uses Ghostty 1.2/1.3 features, but source validation is manual, the optional overlay is unnecessarily home-absolute, and both zsh parity files retain a custom-file source branch that never matches the current local shim. The installed Ghostty 1.3.1 parser validates the existing config and the approved additions.

The worktree contains unrelated changes, including changes to Just, pre-commit, zsh, and docs surfaces. Implementation must use narrow edits and preserve all existing hunks.

## Goals / Non-Goals

**Goals:**

- Adopt `palette-harmonious`, padded-notch non-native fullscreen, and a collision-free URL-copy binding while preserving all existing explicit pins.
- Use `?config.local` as an optional sibling overlay.
- Keep official Ghostty automatic shell integration as the single owner for the initial zsh.
- Enforce static source contracts everywhere and parse an isolated rendered config whenever both required binaries exist.
- Expose the focused gate through Just, pre-commit, scoped guidance, and operator docs.

**Non-Goals:**

- Applying Chezmoi or changing the live Ghostty config.
- Installing, upgrading, or pinning Ghostty.
- Tracking machine-local background, sound, theme, or overlay files.
- Automatically deleting `~/.config/ghostty/shell-integration.zsh`.
- Adding shaders, modal key tables, app-icon changes, output-driven scrolling, or unsupported padding syntax.
- Cleaning or reformatting unrelated dirty work.

## Decisions

### Use a sibling-relative optional overlay

The template will use `config-file = ?config.local`. Ghostty resolves relative includes beside the containing config, which is the intended deployed location and avoids embedding a home-specific path in this directive. An absolute Chezmoi-rendered path was considered but rejected because it creates avoidable source/deployed drift and complicates isolated validation.

### Keep explicit pins and add only validated 1.3 behavior

The existing explicit-default style remains intact. The template will add `palette-harmonious = true`, `macos-non-native-fullscreen = padded-notch`, and `keybind = cmd+alt+u=copy_url_to_clipboard`; the complete candidate set validates on Ghostty 1.3.1 and the chord has no default/current collision.

`window-padding-color = extend-background` is rejected because it is invalid. The supported `extend` value is also omitted: it extends adjacent grid-cell colors rather than the configured PNG background and has no demonstrated benefit for the current image, opacity, and blur composition.

### Let Ghostty own shell integration

The zsh-level Ghostty source branch will be removed from both parity files. `shell-integration = detect` already injects the official initial-shell integration, the active Ghostty environment exposes its official resources, and the custom OSC-777 hook is not loaded. Retaining the branch would preserve dead code and ambiguous ownership.

The untracked shim will not be deleted automatically. Its removal is a separate manual decision after a fresh-session check confirms no external consumer.

### Separate static contracts from native parsing

`checks/ghostty.sh` will always validate tracked file structure and critical content. When both `chezmoi` and `ghostty` are available, it will render the template with `chezmoi execute-template --file` into a private temporary directory and run `ghostty +validate-config --config-file=<path>`.

Stdin validation was considered and rejected because Ghostty 1.3.1 does not accept `--config-file=-`. The real `config.local` will not be copied beside the temporary base config, so repository-source validation is isolated from machine-local overrides. Missing tools skip only native parsing, never static assertions.

Rendered output may legitimately contain `/Users/...` after `.chezmoi.homeDir` expansion for local assets. Hardcoded-home checks therefore apply only to tracked source, not rendered output.

### Make semantic validation discoverable

The check will be listed in `shell_files`, exposed as `just check-ghostty`, included in `just check`, and triggered by a focused pre-commit hook when Ghostty-related sources or docs change. Existing generic shell validation continues to own Bash syntax, ShellCheck, and shfmt enforcement.

Operator docs will distinguish repository-source validation (`just check-ghostty`) from deployed validation (`gtyv`) and active-config inspection (`gtyc`).

## Risks / Trade-offs

- **Non-native fullscreen disables native tabs while fullscreen** → Document the trade-off, test with a single-surface window, and roll back only the `macos-non-native-fullscreen` line if tab behavior is more important.
- **Harmonious generated palettes can break legacy fixed-index assumptions** → Exercise a palette-sensitive TUI and roll back only `palette-harmonious` if readability regresses.
- **Older Ghostty versions may reject the additions** → Rely on native parser failure; do not add compatibility branches.
- **CI may lack Ghostty or Chezmoi** → Keep static contracts mandatory and emit a clear skip for only the rendered parser phase.
- **Relative overlay is absent during isolated validation** → Validate deployed overlays separately with `gtyv` after an approved apply.
- **Target files already contain unrelated changes** → Use exact edits, avoid broad formatters, and review path-scoped diffs before and after each group.

## Migration Plan

1. Create the focused spec and implementation artifacts.
2. Update the template and both zsh parity files without applying them.
3. Add and wire the focused check, then update guidance and docs.
4. Run focused checks, native temporary rendering, full `just check`, docs CI, OpenSpec verification, and `just home-diff`.
5. Apply Chezmoi only after separate explicit approval.
6. In a fresh Ghostty session, validate URL copying, fullscreen, palettes, official shell integration, and absence of duplicate notifications.
7. If needed, roll back individual config lines independently; retain the local shim until its external use is ruled out.

## Open Questions

None. The behavior choices, validation boundary, key chord, and cleanup boundary are resolved.
