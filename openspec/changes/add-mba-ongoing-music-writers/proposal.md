## Why

The MBA needs ongoing imports and its existing Spotify Liked Songs playlist after the initial migration. Writing into a served, immutable music epoch would invalidate the reader's witness. The existing initial E1 publisher cannot be replayed for each import.

## What Changes

- Reuse the current music-writer lock, Beets import verifier, complete census, guarded Navidrome reader and organized-phone publication hook in one normal-account transaction.
- Publish fresh immutable epoch controls for verified new imports and the single existing Liked Songs playlist; preserve old controls and every unrelated file.
- Add the missing guarded reader service lifecycle and explicit writer installation with the existing watch and calendar behavior plus periodic ingest reconciliation for missed events or writer contention.
- Detect unchanged work before stopping the reader or collecting the library census. Keep interrupted effects pending for reconciliation rather than replaying them.
- Reuse the existing Spotify account, export, matcher and sidecar download behavior. Provision only the existing dedicated music credential overlay privately and generate the existing download-tool configuration. No new Navidrome API account, credential store or authentication scope is needed.

## Capabilities

### New Capabilities

- `mba-ongoing-music-writers`: serialized new-import and playlist publication with guarded reader handover.

### Modified Capabilities

None.

## Impact

The implementation is initially a private deployment candidate. Source checks and source staging do not activate writers, publish E1, complete recovery or establish phone delivery. Actual recovered state, capacity, one-owner installation, a pilot and current epoch references remain required before scheduling. The service runs under the existing account, with no root service, new framework, bulk retagging or model work.
