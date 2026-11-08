## ADDED Requirements

### Requirement: Private phone browser with host-owned transfers
The music host SHALL run one pinned normal-user slskd daemon with authenticated
loopback control and private HTTPS. The phone SHALL control searching, browsing
user shares and transfers through its Home Screen web app. Existing network
accounts, private routes and music writers SHALL remain preserved.

#### Scenario: Phone leaves the foreground
- **WHEN** a verified transfer is queued on the music host and the phone locks
- **THEN** the daemon continues independently of the phone browser
- **AND** reconnecting the phone shows the actual current queue state
- **AND** this does not claim the phone's offline library has updated

### Requirement: Pinned explicit user installation
Installation SHALL verify the archive hash, protect owned private state, preserve
credentials on repeat invocation and refuse changed pinned/running closures.
Staging SHALL NOT activate a service. Startup SHALL resolve no dependencies.

#### Scenario: Existing service differs
- **WHEN** the pinned installation or running managed configuration differs
- **THEN** the installer refuses replacement and requires reconciliation
- **AND** existing credentials and active service configuration are preserved

### Requirement: Completion events create candidates only
The intake adapter SHALL admit only versioned persisted file-completion events
whose actual final path is an owned settled regular file within the exact
completed inbox. It SHALL bind complete hashes and lossless native stamps to a
stable transfer identity. Canonical admission SHALL use the existing shared
verifier/promoter and writer.

#### Scenario: Transfer says successful before the move finishes
- **WHEN** transfer state is successful but the completion event/file is absent
- **THEN** no candidate or canonical import is inferred from that state alone

#### Scenario: Repeated completion report
- **WHEN** the same transfer has the same bound path, bytes and hash
- **THEN** the existing immutable candidate is reused without importing twice
- **AND** a conflicting report is held for reconciliation without overwriting it

#### Scenario: Candidate has unresolved release identity
- **WHEN** edition, version or requested format identity remains unresolved
- **THEN** the candidate remains review-required
- **AND** filename, duration or a lossless-looking extension cannot authorize admission
