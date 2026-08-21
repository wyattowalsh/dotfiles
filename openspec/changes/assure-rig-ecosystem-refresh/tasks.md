## 1. Defect-First Checks

- [x] 1.1 Add fkill fixtures for PID 0, PID 1, current-shell PID, malformed/oversized values, duplicates, cancellation, and kill failure.
- [x] 1.2 Add shell structure checks for the exact twelve-plugin set, history sizing/options, pnpm completion, Homebrew-only YSU ordering, highlighting-last, and zshrc mirror parity.
- [x] 1.3 Add Yazi checks for current fields, resolved plugins/flavors, dark/light theme mapping, DuckDB Option keys, and preservation of `g h`, `H`, and `L`.
- [x] 1.4 Add Brew/Git/Nix checks for explicit tmux ownership, nbdime provider linkage, Git config parse/D6 absence, and G4 absence.

## 2. Shell And Home Desired State

- [x] 2.1 Harden `fkill` with decimal/range/self/deduplication guards while preserving cancellation and kill status.
- [x] 2.2 Generate and track `_pnpm` with the pinned pnpm toolchain and verify managed `fpath` ordering.
- [x] 2.3 Make `layout_uv` activation-only and add explicit `layout_uv_sync` using `uv sync --frozen`.
- [x] 2.4 Remove the speculative YSU fallback while retaining after-aliases and before-highlighting load order.
- [x] 2.5 Resolve and track Yazi `git`, `toggle-pane`, `piper`, `rose-pine`, and `rose-pine-dawn` locks in an isolated config home.
- [x] 2.6 Track dark/light Yazi theme mapping and move DuckDB navigation to `<A-h>`/`<A-l>` without overriding presets.

## 3. Curated Package And System State

- [x] 3.1 Record tmux as excluded, or as an exact tracked Agent Deck dependency if that concurrent consumer is present.
- [x] 3.2 Add `uv "nbdime"` and retain notebook attributes plus parseable nbdime driver configuration.
- [x] 3.3 Remove only the three unapproved G4 macOS defaults.
- [x] 3.4 Remove only the unapproved `dft` alias and difftastic tool block while retaining the formula and approved Git behavior.

## 4. External Research Capability Handoff

- [ ] 4.1 Coordinate the agents-repository OpenSpec, `rig-ecosystem-refresh` skill, and `rig-ecosystem-index` workflow implementation.
- [ ] 4.2 Validate dynamic surface discovery, authoritative item/page enumeration, read-only research, continuation manifests, count reconciliation, and approval refusal for incomplete evidence.
- [ ] 4.3 Validate canonical and local workflow bytes plus exactly-one collision-free skill exposure.
- [ ] 4.4 Archive only recognized legacy project/user workflow copies outside discovery roots, verify archive hashes, and remove the originals.

## 5. Documentation And Verification

- [x] 5.1 Update shell, home, package, Git, macOS/Nix, and workflow-facing operator documentation to match the reviewed state and current copyable commands.
- [x] 5.2 Run focused shell/Yazi/Brew/Git/Nix checks, mirror comparisons, syntax/parsing validation, and secrets scan.
- [x] 5.3 Run `just check`, `just ci`, and `just docs-ci`; report source, generated, installed-state, and live-runtime evidence separately.
- [ ] 5.4 Obtain independent safety, all-findings, and skill/workflow/handoff reviews and reconcile every OpenSpec scenario.
- [x] 5.5 Stop before Homebrew/Chezmoi/nix-darwin/LaunchAgent apply, live backup execution, or recommendation integration without a new explicit approval.
