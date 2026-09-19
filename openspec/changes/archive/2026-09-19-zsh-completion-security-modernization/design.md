## Context

The runtime `~/.zshrc` is a symlink to `rig/dots/zshrc`; `rig/home/dot_zshrc.tmpl` is a byte-identical validation mirror. The intended completion model is Model A: every completion path is assembled before `source "$ZSH/oh-my-zsh.sh"`, and Oh My Zsh owns the only `compinit`. Third-party installers appended Grok/CCS blocks with two additional `compinit` calls, while `/opt/homebrew/share` was mode 0775. The final bare `compinit` therefore prompted on every terminal startup.

The repository already pins zsh load-order behavior through `checks/zsh-structure.sh`, fixtures, and `just check-zsh`; macOS bootstrap is dry-run-first and installs the Brewfile before linking the canonical zshrc.

## Goals / Non-Goals

**Goals:**

- Eliminate the interactive completion-security prompt and prevent its return.
- Preserve Model A and fold externally installed completion paths into managed configuration.
- Keep completion cache files out of `$HOME`.
- Add narrowly selected shell UX improvements without abandoning Oh My Zsh or Powerlevel10k.
- Make startup timing reproducible enough to guide later optimization.

**Non-Goals:**

- Replace Oh My Zsh with Antidote or Powerlevel10k with Starship.
- Enable carapace or fzf-tab before interactive UX evaluation.
- Treat timing as a CI performance gate.
- Modify unrelated in-flight music, remote-access, or package work.

## Decisions

1. **Oh My Zsh remains the sole completion initializer.** Grok and CCS contribute only managed `path`/`fpath` entries before Oh My Zsh. Direct `compinit` calls remain forbidden by the structural gate. This preserves the repository's existing completion architecture and avoids duplicate scans and competing dump files.

2. **Secure the filesystem rather than bypassing audits.** Remove `ZSH_DISABLE_COMPFIX`; macOS bootstrap runs `compaudit`, applies `chmod go-w` to reported paths in apply mode, and audits again. Dry-run only reports the planned chmod. A Darwin-only read-only check detects later Homebrew permission regressions. Keeping `compinit -u` was rejected because it silently accepts insecure completion code.

3. **Place `ZSH_COMPDUMP` in XDG cache.** The dump name includes host and zsh version, and its parent is created only when absent. This avoids stale `~/.zcompdump*` clutter while retaining per-host/version invalidation.

4. **Add only low-risk QoL features to the desired state.** `colored-man-pages` uses an existing Oh My Zsh plugin; `zsh-history-substring-search` is Homebrew-managed, sourced after syntax highlighting as required upstream, and owns Up/Down while Atuin retains Ctrl-R.

5. **Measure full interactive initialization through a pseudo-TTY on macOS.** Powerlevel10k/gitstatus behaves differently without a terminal, so raw `zsh -i -c exit` is misleading. The timing recipe reports min/median/max and never gates CI.

6. **Evaluate larger migrations without activating them.** carapace and fzf-tab remain local opt-in trials; Antidote and Starship are deferred until targeted profiling demonstrates that their replacement scope addresses the actual bottleneck.

## Risks / Trade-offs

- **Homebrew restores group/world write bits after an update** → bootstrap normalization and `checks/zsh-compaudit.sh` detect and repair the regression.
- **A compaudit finding is caused by ownership, not mode** → post-normalization audit fails with the remaining paths instead of claiming success.
- **Installer reruns append direct `compinit` again** → L1 structure checks and mirror parity fail.
- **Arrow escape sequences vary by terminal** → bind both common CSI and application-mode sequences; document how to revisit if a terminal differs.
- **Pseudo-TTY timings vary with cold caches and background load** → report a range, not a threshold; use `zprof` before architectural migration.
- **Canonical and mirror zshrc diverge** → update both together and retain byte-parity checks.

## Migration Plan

1. Repair the live Homebrew completion parent with `chmod go-w` and verify `compaudit` is empty.
2. Update canonical zshrc and its mirror, then immediately run zsh syntax and pseudo-TTY startup checks because the canonical file is live-linked.
3. Install and record the selected Homebrew plugin; move completion dumps to XDG cache and remove obsolete home-directory dumps.
4. Update bootstrap, structural/behavior checks, fixtures, Just recipes, and documentation.
5. Verify `just check-zsh`, focused shell lint, docs checks, a clean pseudo-TTY startup, completion bindings, cache location, and timing output.

Rollback uses version control for repository files and `checks/zsh-rollback-live.sh` for live zsh recovery. Restoring `ZSH_DISABLE_COMPFIX=true` is not part of rollback; filesystem security should remain fixed.

## Open Questions

- After a real-terminal trial, should carapace or fzf-tab be promoted into the Brewfile and managed zshrc?
- A TTY-aware `zprof` run is still needed before changing prompt/plugin architecture or deferring slow integrations.
