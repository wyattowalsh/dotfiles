# Security Topic

Owns no-secrets policy, secret scanning, and safe import boundaries.

## Rules

Never track:

- Passwords, API keys, bearer tokens, private keys
- OAuth/auth databases, session stores, histories
- Raw inventory with secret-shaped path components (use redacted inventory)

## Tooling

```bash
just secrets-scan      # tracked files only; requires rg
just inventory-redacted  # scrubbed paths, no contents
```

## Agent instructions

Root `AGENTS.md` § No secrets policy applies to all subsystems. Run `just secrets-scan` before commits that touch MCP or credential-adjacent config.