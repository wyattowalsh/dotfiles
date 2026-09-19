## 1. Repair Live Completion Security

- [x] 1.1 Audit the live fpath and remove group/world write bits from `/opt/homebrew/share`.
- [x] 1.2 Verify `compaudit` is empty and a pseudo-TTY terminal starts without an insecure-directory prompt.
- [x] 1.3 Remove obsolete `~/.zcompdump*` files and lock directories.

## 2. Restore Managed Completion Ownership

- [x] 2.1 Remove installer-appended Grok/CCS `compinit` blocks from the canonical zshrc.
- [x] 2.2 Fold Grok/CCS PATH and completion directories into the managed pre-Oh-My-Zsh blocks.
- [x] 2.3 Move `ZSH_COMPDUMP` to the host/version-specific XDG cache path and remove `ZSH_DISABLE_COMPFIX`.
- [x] 2.4 Keep `rig/dots/zshrc` and `rig/home/dot_zshrc.tmpl` byte-identical.
- [x] 2.5 Move the tracked pnpm `#compdef` marker to line 1 and preserve reproducibility testing.

## 3. Add Curated Shell Quality Improvements

- [x] 3.1 Add `zsh-history-substring-search` to the Brewfile and install it locally.
- [x] 3.2 Source history-substring-search after syntax highlighting, enable unique results, and bind Up/Down sequences.
- [x] 3.3 Add the Oh My Zsh `colored-man-pages` plugin and update the pinned plugin contract.
- [x] 3.4 Measure and document carapace, fzf-tab, Antidote, and Starship without activating architectural replacements.

## 4. Add Durable Bootstrap and Validation Guardrails

- [x] 4.1 Add macOS bootstrap permission normalization with dry-run behavior and post-apply re-audit.
- [x] 4.2 Add the Darwin-only `checks/zsh-compaudit.sh` gate and wire it into `just check-zsh`.
- [x] 4.3 Extend zsh structure checks and mutation fixtures for plugin order, cache placement, compfix policy, history-search source, and bindings.
- [x] 4.4 Add a report-only, pseudo-TTY-aware `just zsh-time [N]` helper.

## 5. Documentation

- [x] 5.1 Update shell, package, validation, fresh-mac, and bootstrap-agent documentation.
- [x] 5.2 Record the architecture, requirements, migration, rollback, and candidate evaluation in OpenSpec.

## 6. Verification

- [x] 6.1 Run the complete focused zsh suite, touched-file shell lint, Just formatting, and diff whitespace checks.
- [x] 6.2 Verify live Up/Down bindings, pnpm/CCS/Grok completions, XDG dump location, compaudit cleanliness, and pseudo-TTY startup.
- [x] 6.3 Run documentation validation and record any aggregate-suite blockers caused by unrelated dirty worktree changes.
