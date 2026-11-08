## Why

The phone needs a straightforward Soulseek browser while the music host owns
long-running network transfers and the existing verified library pipeline.

## What Changes

- Pin the official self-contained Apple Silicon slskd release and prepare an
  idempotent normal-user installation with separate private account material.
- Keep web control on loopback; use the existing Tailscale installation for
  private HTTPS and a Safari Home Screen entry.
- Capture persisted completion events as immutable review-required candidates.
  Reuse the shared verifier/promoter and canonical writer for admission.
- Include exact service and transfer state in existing recovery/startup coverage.

## Capabilities

### New Capabilities

- `mba-phone-soulseek`: private phone-controlled Soulseek browsing and verified intake.

### Modified Capabilities

None.

## Impact

This adds a normal-user daemon and a bounded local read-only intake adapter. It
does not replace Sockseek, create a canonical writer or change existing MCP
routes. Installation, network login, real phone browsing, transfer, canonical
admission and recovery are separate acceptance layers.
