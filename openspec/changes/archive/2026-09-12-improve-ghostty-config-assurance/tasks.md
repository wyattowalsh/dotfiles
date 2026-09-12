## 1. Ghostty Desired State

- [x] 1.1 Update the optional overlay, palette, fullscreen, URL-copy binding, and validation comments in `rig/home/private_dot_config/ghostty/config.tmpl` while preserving existing explicit pins.
- [x] 1.2 Remove the inert Ghostty custom-source branch from `rig/home/dot_zshrc.tmpl` and `rig/dots/zshrc` while preserving Cursor integration and byte parity.

## 2. Focused Validation

- [x] 2.1 Add `checks/ghostty.sh` with aggregate static contracts for the template, data keys, zsh ownership/parity, workflow wiring, and documentation.
- [x] 2.2 Add conditional isolated Chezmoi rendering and native Ghostty path-based parsing with safe temporary cleanup and a clear missing-tool skip.
- [x] 2.3 Add `checks/ghostty.sh` to `shell_files`, expose `just check-ghostty`, and include it in the aggregate `just check` recipe.
- [x] 2.4 Add the path-scoped `dotfiles-ghostty-config` pre-commit hook without changing existing generic shell coverage.

## 3. Guidance and Documentation

- [x] 3.1 Update `rig/home/AGENTS.md` for the sibling-relative overlay and retained `.chezmoi.homeDir` asset-path rule.
- [x] 3.2 Update `terminal.mdx`, `validation.mdx`, `home-config.mdx`, and `shell.mdx` with the approved behavior, validation boundaries, and rollback caveats.
- [x] 3.3 Run `/docs-steward` and reconcile relevant findings without editing generated docs output.

## 4. Verification

- [x] 4.1 Run shell formatting/lint, shell-file ledger, zsh parity, focused Ghostty, hooks, Just formatting, and focused pre-commit validation.
- [x] 4.2 Render the template directly to a temporary file and validate it with Ghostty 1.3.1.
- [x] 4.3 Run `just check`, `just docs-ci`, `just secrets-scan`, and `just home-diff`; inspect only scoped diffs and preserve unrelated dirty work.
  - Full aggregate green after fixing pre-existing blockers: shfmt in `iina-config.sh`/`spicetify.sh`, shell-file ledger intent-to-add entries, the mise-python3 freshen harness contamination, and the flaky interrupt PID observation window.
- [x] 4.4 Verify the OpenSpec change and leave Chezmoi apply plus local-shim cleanup for separate explicit approval/manual acceptance.
