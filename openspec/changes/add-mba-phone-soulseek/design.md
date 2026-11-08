## Architecture

Phone Safari/Home Screen → private Tailscale Serve HTTPS → authenticated slskd
loopback web UI/API → private incomplete/completed inbox → persisted completion
event adapter → immutable review-required candidate → existing verifier/promoter
and canonical epoch writer → existing recovery/feed publication.

## Decisions

- Use the pinned native ARM64 binary; no Docker or .NET SDK is needed at runtime.
- Separate the daemon's network account from Qt/Sockseek sessions. Generate and
  retain credentials only on the target, with owner-only files and directories.
- Stage an inactive launcher first; activation deliberately installs the user
  LaunchAgent. Never resolve dependencies or download packages during startup.
- Preserve exact existing versions/configurations on drift; do not overwrite a
  running different closure or reset Serve mappings.
- Initial sharing is empty until the exact share scope is reviewed.
- Use the persisted `DownloadFileComplete` event version 0 for actual final paths.
  The upstream successful transfer state precedes file movement and cannot prove
  settled completion. All candidate data remain untrusted identity evidence.
- The adapter uses GET only, bounded pages, nonblocking ownership, complete file
  hashes and before/after native stamps. It writes no canonical state.
- Repeated reports reuse an equal immutable transfer candidate. Conflicting
  reports require reconciliation. Unknown versions and incomplete/changed files
  stay held; finite page bounds remain explicit.

## Recovery

Retain the original inbox files and all candidate receipts. Capture the exact
package/configuration/launcher and native database state consistently before
cleanup. An isolated restore must not activate the same network identity.
