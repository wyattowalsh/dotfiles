# AI Topic

Owns AI client configuration strategy, agent/skill boundaries, and generated config review.

## Canonical SSOT

- `ai/` — MCPHub manifests, client surfaces, templates
- `setup.sh` — Linux path installs CLIs + skills (`claude`, `gemini`, `copilot`, `codex`)

macOS full-rig bootstrap does not yet install AI CLIs; install manually or extend bootstrap when promoted.

## Policy

- Skills from `wyattowalsh/agents` via `setup.sh` on Linux
- Universal skills mirrored to per-agent skill dirs when CLIs exist
- Provider auth remains manual after install

## Validation

```bash
just ai-check
```