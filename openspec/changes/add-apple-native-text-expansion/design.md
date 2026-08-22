## Context

Apple Text Replacement is the right store for static phrases. Apple Shortcuts cover menus, dates, and an explicit Expand Anywhere paste. The live library is inventory: promote curated triggers into git, preserve unrelated entries, keep `myaddr` in a 0600 overlay.

## Goals / Non-Goals

**Goals**

- Single public registry in this repo
- Preserve-by-default merge from a user-dragged plist
- Redacted plans (fingerprints, never private phrases)
- Shortcut recipes as Describe-a-Shortcut text, not compiled binaries

**Non-goals**

- `defaults` / SQLite writes into Apple databases
- Typed trigger → Shortcut execution
- Vendoring MCP/harness JSON

## Decisions

1. **Dotfiles owns replacement logic.** Agents may list trigger names and point here.
2. **Drag-import only.** Stage a plist; the operator drops it on Text Replacements.
3. **`--apply` is explicit.** Default CLI is dry-run.
4. **Namespaces** `my` `msg` `ai` `dev` `md` `sym` plus `==+` `mdash` `ndash` `w4w`.

## Risks / Trade-offs

- Apple export formats vary (`shortcut`/`phrase` vs `replace`/`with`). The parser accepts those keys only.
- Live import still needs a human in System Settings.
