# freshen Function Instructions

## Scope

Zsh autoloadable `freshen` and tests under `home/dot_zsh/functions/`.

Deployed to `~/.zsh/functions/` via Chezmoi (`home/dot_zsh/functions/`).

## Development rules

- Preserve `#compdef freshen` and autoloadable single-file UX unless explicitly changing API
- TDD for behavior changes: failing test in `tests/freshen_test.zsh` first, then minimal fix
- Before completion:

```bash
just check-freshen
```

Version SSOT: `home/dot_zsh/functions/freshen.VERSION` (run `./checks/freshen-version.sh` after bumps).

- `FRESHEN_TEST_KEEP_TMP=1` only when debugging test artifacts

## Safety invariants

- `--dry-run` must not mutate Homebrew, mas, caches, or dev-prune targets
- `--clean-only --dry-run` skips upgrade inventory and all mutations
- Noninteractive mutations require `--yes`
- `--progress=plain --no-color` — no ANSI cursor controls, color escapes, bells, or animations
- Dev-prune must never fall back to `rm` and must refuse broad roots
- Interrupts return 130; clean up child processes and temp files
