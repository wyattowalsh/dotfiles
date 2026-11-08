# AGENTS

## Scope

Apple-native text expansion desired-state. Canonical phrases and Shortcut recipes live here; Chezmoi deploys them to `~/.config/apple-text/`. Merge/stage logic lives in `checks/apple_text.py` (not in wyattowalsh/agents).

## Rules

- Runtime expanders are only Apple Text Replacement and Apple Shortcuts.
- Do not write `TextReplacements.db` or `NSGlobalDomain` replacement keys.
- Do not fabricate `.shortcut` files. Export Describe-a-Shortcut prompts only.
- Public JSON must not contain `myaddr` phrases, phone numbers, tokens, or recovery codes.
- Overlay `~/.config/apple-text/expansions.local.json` is local-only, mode `0600`, chezmoi-ignored.
- Triggers are `;[a-z]{2,5}` plus retained exceptions `==+`, `myEn`, and `w4w`.
- `;panel` is reserved for a saved browser bookmark and is not a replacement.
- `myEn` stays. Do not retire it in favor of `;full`.
- `identity.site` stays `w4w` (`https://w4w.dev`). `;site` is a separate record (`https://www.w4w.dev`).
- Generate `;help` from registry metadata. Do not store a hand-written help phrase.
- Home address and phone stay in the local overlay. Do not put those phrases in public JSON.
- Placeholders are exactly `⟦FIELD⟧`. No `{{today}}` / `$clipboard` in Text Replacements.
- Preserve unrelated live replacements. Known predecessors migrate only when the live phrase matches the recognized baseline.
- `;pnl` is the panel trigger. Do not add `;panel`.
- Typing a Text Replacement trigger never runs a Shortcut. Expand Anywhere is an explicit hotkey.
- Mutating CLI defaults to dry-run (`just apple-text stage`); `--apply` is explicit.
- Operator runbook: `docs/content/docs/apple-text.mdx`.
