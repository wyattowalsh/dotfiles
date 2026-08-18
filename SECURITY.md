# Security

This is a personal public dotfiles repository. There is **no private paid support**.

## Reporting

- Tracked config, bootstrap, docs, and CI: GitHub issues or security advisories on this repository.
- AI harness, MCP servers, and agent-client bugs: [wyattowalsh/agents](https://github.com/wyattowalsh/agents).

Do **not** include secret values, tokens, API keys, or private keys in reports.

## Scanning

```bash
just secrets-scan
```

checks tracked files without printing secret values. Env var **names** belong in `.env.example`; values stay local.
