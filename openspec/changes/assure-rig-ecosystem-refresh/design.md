## Context

The accepted refresh touched independent desired-state surfaces, while review found both direct defects and changes that exceeded the approved recommendation set. The repository is a public dotfiles SSOT; live machine state is inventory, operator docs live under `docs/content/docs/`, and AI harness/workflow assets belong in `wyattowalsh/agents`.

The existing dotfiles Rhai workflow hard-codes a local path, a dated surface inventory, and executable catalog workers. It cannot demonstrate that every catalog item and current first-party documentation page was reconciled, and it does not report failed item identifiers before soliciting approval.

Review traceability:

| Finding | Contract |
| --- | --- |
| RV-S-002 | Reject special, self, malformed, oversized, and duplicate PIDs in `fkill` |
| RV-S-006 | Lock all referenced Yazi plugins and use valid fully qualified package commands |
| RV-S-007 | Record tmux as excluded unless a tracked consumer makes it intentional |
| RV-S-008 | Remove the unapproved G4 macOS defaults |
| RV-S-009 | Generate and track `_pnpm` |
| RV-S-010 | Replace the stale workflow with a dynamic, read-only, reconciled agents-owned capability |
| RV-S-011 | Provide nbdime for active notebook attributes |
| RV-S-012 | Separate uv activation from explicit synchronization |
| RV-S-013 | Pin reviewed shell and Yazi invariants in focused checks |
| RV-S-014 | Lock and map both Rosé Pine flavors |
| RV-S-015 | Use the Homebrew YSU source only |
| RV-S-016 | Reconcile all affected operator docs with tracked behavior |
| RV-S-017 | Remove unapproved D6 Git wiring |
| RV-S-018 | Move DuckDB navigation without shadowing Yazi presets |

## Goals / Non-Goals

**Goals:**

- Close RV-S-002 and RV-S-006 through RV-S-018 with focused, testable desired state.
- Restore the exact approved recommendation boundary by reverting G4 and D6 wiring.
- Make tracked Yazi, pnpm, uv, tmux, and nbdime state reproducible from the repository.
- Retire the unsafe dotfiles workflow only after an agents-owned replacement validates.
- Keep all pre-approval ecosystem research read-only and make completeness machine-verifiable.

**Non-Goals:**

- Modify AI harness, skill, workflow, MCP, or client configuration inside this repository.
- Clean unrelated local workflow/skill duplicates or other pre-existing dirty work.
- Install packages, apply Chezmoi or nix-darwin, run live backup work, commit, or push.
- Treat unavailable upstream documentation as complete coverage.

## Decisions

### Reject unsafe or ambiguous process identifiers before selection

`fkill` accepts decimal identifiers only, bounds them to `2..2147483647`, excludes the current shell, and deduplicates the final selection. fzf cancellation returns the original fzf status without invoking `kill`, while real kill errors remain observable. PID 0 and 1 are never passed to `kill`.

### Separate uv environment activation from mutation

`layout_uv` only activates an already-present environment and returns an actionable error otherwise. `layout_uv_sync` is the explicit opt-in operation that runs `uv sync --frozen` and then activates. This removes hidden network/package mutation from routine direnv evaluation.

### Track generated completion and package locks

Generate `_pnpm` with the repository's current pinned pnpm toolchain and track it under the managed completion directory already added to `fpath`. Resolve Yazi package and flavor refs in an isolated temporary config home, then track the resulting locks for `git`, `toggle-pane`, `piper`, `rose-pine`, and `rose-pine-dawn`.

Yazi uses dark `rose-pine` and light `rose-pine-dawn`. DuckDB horizontal actions move to `<A-h>` and `<A-l>`, preserving preset `g h`, `H`, and `L` navigation.

### Match the approved state exactly

- Keep `tmux` in the Brew exclusion file when no tracked consumer owns it. If a concurrent tracked change adds Agent Deck, permit `tmux` only beside the exact Agent Deck formula and remove the contradictory exclusion.
- Keep notebook attributes and add `uv "nbdime"` to provide their configured driver.
- Remove only the three unapproved G4 macOS defaults.
- Remove only the unapproved `dft` alias and difftastic tool wiring; retain the existing difftastic formula.
- Source `zsh-you-should-use` from Homebrew only, after aliases and before syntax highlighting.
- Preserve exactly twelve Oh My Zsh plugins and enforce the established history/highlighter contracts.

### Hand research ownership to the agents repository

The public capability is `rig-ecosystem-refresh`; its native Grok workflow is `rig-ecosystem-index`. The agents repository owns both. Dotfiles may retain ignored run artifacts under `local/rig-ecosystem/`, but no harness/client configuration.

The replacement dynamically discovers repo-allowed surfaces, enumerates authoritative catalogs, inventories current first-party documentation per item, and emits stable item/page IDs with counts and evidence hashes. Pre-approval child jobs are read-only. A run is approval-eligible only when catalog, item, and documentation counts reconcile with zero failed, pending, or stale identifiers. Budget exhaustion produces a continuation manifest and a `partial` result, never an exhaustive claim.

Integration requires an unchanged board digest, exact recommendation IDs, unchanged target hashes, and explicit user approval. Partial, stale, or mismatched evidence fails closed.

### Migrate recognized workflow copies recoverably

Validate the canonical agents-owned skill/workflow and user projection before retiring the dotfiles copy. Only workflow copies whose bytes match the recorded legacy SHA-256 may be moved automatically. Archive the project copy beneath ignored local state and the user copy beneath user state, both outside workflow discovery roots, and verify archive hashes before removing originals. A divergent destination or legacy copy blocks migration.

## Risks / Trade-offs

- **Generated completion or lock drift** → Record generator/tool versions and validate reproducibility in temporary homes.
- **Brew desired state differs from the current machine** → Report that as expected installed-state evidence; do not install during source assurance.
- **Yazi custom keys shadow presets** → Test absence of `g h`, `H`, and `L` overrides and parse with the tracked config.
- **Cross-repository replacement is incomplete** → Keep the legacy workflow discoverable until canonical and projected replacement validation passes.
- **Research budget cannot cover the universe in one run** → Persist a continuation manifest and make partial status ineligible for approval.
- **Upstream source changes during a long run** → Revalidate authoritative catalogs at final reconciliation and mark stale evidence explicitly.

## Migration Plan

1. Land failing focused checks for each reviewed state contract.
2. Apply shell/direnv, Yazi, Brew/Git/Nix, and documentation corrections with exclusive file ownership.
3. In `wyattowalsh/agents`, create and validate the `rig-ecosystem-refresh` skill and `rig-ecosystem-index` workflow through its own OpenSpec change.
4. Validate both repositories and perform independent all-findings and security reviews.
5. Project the validated workflow locally, confirm exactly one skill exposure, then archive only recognized legacy workflow copies outside discovery roots.
6. Run the installed capability read-only; present recommendations only after complete reconciliation.

Rollback restores recognized archived workflow bytes only after removing or disabling the replacement capability. Source changes in this repository roll back through version control; no live package or machine-state rollback is required because those applies remain out of scope.

## Open Questions

None. Package providers, key bindings, approval boundary, workflow names, migration hash, and local-install ownership are fixed by the approved plan.
