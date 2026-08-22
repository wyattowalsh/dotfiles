## Why

Static identity, message, and AI snippets on this Mac must stay Apple-native (Text Replacement + Shortcuts) and versioned with the rest of the rig. Putting the phrase registry and merge logic in wyattowalsh/agents would split machine desired-state away from Chezmoi/home.

## What Changes

- Canonical public expansions and Shortcut recipes under `rig/home/private_dot_config/apple-text/`
- Stdlib Python merge/stage CLI (`checks/apple_text.py`) with bash entry `checks/apple-text.sh`
- Local overlay for `myaddr` (chezmoi-ignored, mode 0600)
- Dry-run staging of a user-dragged Apple plist; never write `TextReplacements.db`
- Operator runbook `docs/content/docs/apple-text.mdx`

## Capabilities

### New Capabilities

- `apple-text`: Apple Text Replacement and Shortcuts desired-state, redacted merge, and dry-run staging for this rig.

### Modified Capabilities

None.

## Impact

- Chezmoi home JSON, checks, just recipes, docs hub/sidebar, nested `AGENTS.md`
- Agents repo should point here for phrases; it must not keep a second registry SSOT

## Non-goals

- Writing Apple internals or fabricating `.shortcut` files
- Third-party expanders
- Claiming iPhone/iPad sync from this change
- Committing street address, phone, tokens, or recovery codes

## Validation

- `just check-apple-text` and `just check-bats`
- `just docs-ci` and `just secrets-scan`
- Live Mac: wait for a user-dragged Text Replacement export before claiming import
