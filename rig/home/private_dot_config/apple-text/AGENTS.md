# AGENTS

## Scope

Apple-native text expansion desired-state. Canonical phrases and Shortcut recipes live here; Chezmoi deploys them to `~/.config/apple-text/`. Merge/stage logic lives in `checks/apple_text.py` (not in wyattowalsh/agents).

## Rules

- Runtime expanders are only Apple Text Replacement and Apple Shortcuts.
- Do not write `TextReplacements.db` or `NSGlobalDomain` replacement keys.
- Do not fabricate `.shortcut` files. Export Describe-a-Shortcut prompts only.
- Public JSON must not contain `myaddr` phrases, phone numbers, tokens, or recovery codes.
- Overlay `~/.config/apple-text/expansions.local.json` is local-only, mode `0600`, chezmoi-ignored.
- Namespaces: `my…`, `msg…`, `ai…`, `dev…`, `md…`, `sym…`. Exceptions: `==+`, `mdash`, `ndash`, `w4w`.
- Placeholders are exactly `⟦FIELD⟧`. No `{{today}}` / `$clipboard` in Text Replacements.
- Preserve unrelated live replacements (`myphone`, `mysite`, and any other non-canonical trigger).
- Typing a Text Replacement trigger never runs a Shortcut. Expand Anywhere is an explicit hotkey.
- Mutating CLI defaults to dry-run (`just apple-text stage`); `--apply` is explicit.
- Operator runbook: `docs/content/docs/apple-text.mdx`.
