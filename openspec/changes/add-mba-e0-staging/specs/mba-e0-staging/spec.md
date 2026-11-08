## ADDED Requirements

### Requirement: Guarded native reader requires recovered application state
The MBA Navidrome reader SHALL require an independently verified consistent database restore from the final selected support export before first start, in addition to the existing E1 media/host/volume contract. The final source support capture SHALL occur with source Navidrome, ingest and likes quiescent so the last native playback/history changes are retained. The private restore witness SHALL bind exact support-export and distinct backup/restore receipt hashes, the same observed native binary version, a standalone restored DB hash and dynamic exact native counts and identity fingerprints. Personal counts, user rows and source paths SHALL NOT become tracked policy constants.

#### Scenario: Fresh or altered native database
- **WHEN** the target database is absent, empty, replaced or differs from its admitted restored bytes/counts/IDs at first start
- **THEN** no reader starts and no fresh catalog is substituted
- **AND** a source-only export, earlier state capture, changed witness, incompatible native version or partial WAL tuple does not establish restoration

#### Scenario: Matching restore and subsequent native updates
- **WHEN** the independently recovered standalone DB matches the admitted selected export and native version
- **THEN** first start durably binds its witness and DB identity before spawning the reader
- **AND** that binding is restoration admission only, not native startup or playback proof
- **AND** later legitimate native DB writes remain usable under the same admission while replaced, truncated and fresh catalogs remain refused
- **AND** existing E1, loss/rearm, lease and uncertain-cleanup interlocks remain authoritative

#### Scenario: Internal Data-volume database after reboot
- **WHEN** the internal Data-volume reader's database retains its admitted inode and the actual APFS UUID, Data role and internal device-node observation match its configured volume
- **THEN** schema version 2 of the restoration admission retains the UUID/inode identity across boot-local device-number changes
- **AND** the original restored hash/witness custody and subsequent native-update checks remain authoritative
- **AND** a changed UUID, inode or volume role is refused, while the separately configured external-media topology retains strict writable-database device/inode custody

#### Scenario: Native identity preservation
- **WHEN** the recovered reader root changes to the exact published MBA E1 tree
- **THEN** the supported default library ID and relative native paths/IDs are preserved
- **AND** no global path replacement, identity regeneration, replacement user creation or fresh audio rescan is used as database recovery

### Requirement: Likes format presence requires measured codec and bitrate

The existing likes matcher SHALL retain beets bitrate and SHALL count an MP3
as satisfying its320kbps slot only with exact320000 bitrate and matching bounded
MPEG Layer III header evidence. Lossless presence SHALL use matching FLAC or
PCM/float WAVE/AIFF codec headers, not suffix/container assumptions. Unknown or
contradictory evidence SHALL leave the format missing. These observations SHALL
NOT claim original-master provenance or whole-stream CBR.

#### Scenario: A matched version has only a192kbps MP3

- **WHEN** the same verified version lacks a lossless file and exact320 MP3
- **THEN** its existing queue requests both formats and retains the192kbps original
- **AND** it does not fabricate a radio/extended companion, transcode, cut or retag

#### Scenario: A WAVE contains a lossy codec

- **WHEN** its container suffix and beets format say WAVE but the codec is lossy
- **THEN** it does not satisfy lossless presence
- **AND** no source file, database or installed writer is modified by the check

### Requirement: Explicit additive production staging
The existing staging CLI SHALL retain its default read-only plan and SHALL provide an explicit E0-only production operation bound to a private frozen census and operator contract. The target SHALL be a new private root with pinned host, directory, APFS Data volume and capacity identities. Production SHALL pull one file at a time over strict SSH using the named key and host pins, without interactive prompts or inherited SSH configuration.

#### Scenario: Complete a staged E0
- **WHEN** the frozen source and target match and every eligible file streams successfully
- **THEN** each temporary file is fully hashed, synced and exclusively renamed, followed by full target readback and a complete source recheck
- **AND** the tree remains unserved, with no E1 publication, source deletion or writer handover

#### Scenario: Capacity or identity changes
- **WHEN** live reserve checks fail, a pinned identity changes or the source differs from the census
- **THEN** the operation stops without overwriting final files or publishing the tree
- **AND** partial bytes and private journal evidence remain available

### Requirement: Explicit whole-census capacity
The frozen production contract SHALL optionally admit `max_entries` as an integer from 1 through 100,000, defaulting to 10,000. The complete manifest byte bound SHALL be the greater of 24,000,000 bytes and `max_entries * 2,400`, with 65,536 additional bytes for the outer receipt envelope. The identical entry bound SHALL govern target validation, source envelope loading and the final source collector. Partial manifests SHALL NOT be accepted as independent batches or summed into complete coverage.

#### Scenario: Measured library exceeds the default
- **WHEN** the frozen contract explicitly specifies `max_entries: 100000`
- **THEN** one complete manifest with more than 10,000 and at most 100,000 rows may be validated, copied and independently rechecked under the same bound
- **AND** this bound is part of the immutable campaign digest; changing it does not adopt an existing campaign

#### Scenario: Default or conflicting bounds
- **WHEN** no contract override is supplied or an explicit CLI limit conflicts with the frozen contract
- **THEN** the default remains 10,000 entries or the conflicting operation is refused, respectively
- **AND** ordinary directory rows classified only as `not_regular_file` remain distinct from unresolved eligible-file blockers

### Requirement: Preserve supported originals and retained companions
Policy `st01-v2-originals` SHALL preserve the existing ingest's supported original audio formats under the measured music roots, recognizing root-label case without renaming literal paths. Valid Unicode format characters in existing names SHALL remain literal; controls, traversal, collisions, nonlocal entries and untrusted ancestry SHALL remain refused. Production copy and whole-set comparison SHALL include retained companions independently of serving and phone eligibility. Existing explicit transient exclusions SHALL NOT authorize deletion.

#### Scenario: Original formats, covers and companions
- **WHEN** Wave/WAV, AIFF/AIF, AAC/M4A and the other supported originals, multiple artwork candidates, or non-audio companions occur in the frozen library
- **THEN** the original files and companion bytes are preserved in the copied set
- **AND** retained movies, CUE/NFO/SFV/TXT or unknown non-audio files do not acquire an unsupported playback/phone claim

#### Scenario: Album and canonical playlists
- **WHEN** a playlist uses root-relative, album-relative, internal-parent, Windows-separator or same-root absolute references
- **THEN** the census resolves only unique matches within its complete observed regular-file set, preserving original bytes, whitespace, order and repeated tracks
- **AND** unusable or undecodable playlists remain hashed retained companions rather than being discarded or asserted playable

### Requirement: Durable idempotent recovery
Production SHALL hold one exclusive campaign lease, bind durable control state to the exact campaign/census/capacity contract and preserve interrupted attempt history. Journal state SHALL live outside the staged media tree. A prior completion SHALL count as current only when the matching verification run is marked verified.

#### Scenario: Resume verified files
- **WHEN** a campaign resumes with the identical contract and verified journaled final files
- **THEN** it rechecks their complete hashes and retains their inode rather than overwriting or recopying them

#### Scenario: Resume an interrupted partial
- **WHEN** a pre-journal has a safe partial and no final file
- **THEN** the partial is retained outside the media tree with attempt history before a fresh single temporary file is allocated

#### Scenario: Recover after rename
- **WHEN** a verified final file exists with the matching pre-journal and no temporary file
- **THEN** recovery may finish its journal only after complete byte and pathname verification
- **AND** unrecorded, changed or missing completed files remain failures rather than automatic overwrite/replay

#### Scenario: Reverification fails
- **WHEN** a new run cannot complete source or target verification
- **THEN** its durable run state remains incomplete and an older result cannot establish success for that run

### Requirement: Anchored historical pre-E0 capacity
The existing v3 evaluator SHALL optionally accept an exact pre-E0 anchor binding the E0 epoch, start timestamp, frozen measurement digest and start-receipt digest. Pre-E0 measurements SHALL be fresh at that frozen start, while the post-E0 observation SHALL remain fresh at evaluation. Supplied receipt references SHALL remain explicitly unverified offline.

#### Scenario: Long or cross-date E0 transfer
- **WHEN** an anchored campaign spans more than one hour or a UTC date boundary
- **THEN** the frozen historical pre-E0 measurement may be evaluated against its actual start and a fresh real post-E0 measurement
- **AND** a mismatched epoch, changed frozen measurement, invalid ordering or stale post observation is refused

#### Scenario: Existing capacity consumers
- **WHEN** v2 or unanchored v3 input is supplied
- **THEN** its existing schema and freshness behavior remain unchanged

### Requirement: Source proof remains separate from live acceptance
Disposable tests SHALL exercise the production writer and actual read-only source process with transport/OS observation substituted. Those tests SHALL NOT establish real SSH, macOS APFS, capacity, media recovery, playback, publication or cleanup acceptance.

#### Scenario: Source validation succeeds
- **WHEN** focused tests and specification checks pass
- **THEN** root still owns actual backup/capacity/census/transfer and E1/recovery execution using the existing accepted mission boundaries

### Requirement: Preserve migrated service ownership across reapply
Normal Chezmoi projection SHALL withhold the legacy ingest, likes and Navidrome LaunchAgents and legacy Navidrome TOML on the named Darwin accounts `w4w-mbp`/`ww` and `MacBookAir`/`wyattwalsh`. Legacy music installation SHALL refuse the matching native hostname/account/UID tuples before copying, rendering, acquiring provider credentials or invoking launchctl. Dry-run SHALL describe this retirement without destination writes. Pueue SHALL remain installed with Brew service restart disabled. Existing MBA contract installation SHALL remain the authority for guarded service activation and canonical paths; no generic role framework SHALL be added.

#### Scenario: Reapply on the paired Macs
- **WHEN** the named MBP or MBA account renders home configuration or invokes a legacy music installer
- **THEN** it cannot recreate the old service definitions through Chezmoi or activate them through the installer
- **AND** Pueue dependency reapply does not request service restart
- **AND** existing MBP backup/workstation tools and retained rollback files are preserved

#### Scenario: Explicit rollback or live retirement
- **WHEN** rollback or installed service retirement is required
- **THEN** the operator uses the retained, reviewed plists and matching live case rather than the blocked legacy installer
- **AND** source ignores neither delete installed files nor prove service shutdown, data recovery or single-owner acceptance

#### Scenario: Unrelated identity
- **WHEN** a different host/account renders the same source or an installer observes a nonmatching native UID
- **THEN** the paired-host source rule does not silently change that identity's existing behavior

### Requirement: MBA AC-only host availability
An explicitly installed normal-user MBA Aqua LaunchAgent SHALL run only `/usr/bin/caffeinate -s`, with RunAtLoad and KeepAlive, after verifying the named Darwin hostname/account/UID. It SHALL NOT be installed by generic rig/Chezmoi apply or alter MBP settings, root power settings, display sleep or battery policy. Lid-sleep override and pre-FileVault availability SHALL remain unclaimed.

#### Scenario: Native AC assertion readback
- **WHEN** the exact agent is loaded on the MBA
- **THEN** acceptance binds its PID/UID/argv to its own native PreventSystemSleep assertion and observed AC power
- **AND** native idle-prevention evidence and next-login/lock behavior remain explicit live checks rather than inferred from plist source
- **AND** a missing assertion does not trigger a silent all-power idle flag or pmset change

#### Scenario: Explicit disable
- **WHEN** the operator disables this exact matching agent
- **THEN** only that normal-user label is booted out and disabled, its plist is retained, and other services and power settings are preserved

### Requirement: Explicit reviewed companion-edition queue
The matcher SHALL accept an optional owned, bounded companion CSV with unique edition IDs and exactly one verified existing Spotify or beets parent. Verified targets SHALL retain explicit extended/radio identity, exact metadata and evidence; unresolved targets SHALL remain visible without queueing. It SHALL preserve separate version/format cells, exports and media. Operator attestation SHALL NOT be presented as automatic catalog/audio proof or completed acquisition.

#### Scenario: Both associated editions are known
- **WHEN** separate verified extended and radio declarations are provided
- **AND** each supplies exact target performer/title/album/duration, optional known ISRC and retained identity/association evidence
- **THEN** each edition independently requests its missing lossless and exact320 MP3 formats through the existing queue
- **AND** its full title/remixer text, target duration, evidence and edition ID survive queue creation, with separate retry state
- **AND** the target queue's Spotify ID identifies only its real parent export row

#### Scenario: Owned library family has no Spotify parent
- **WHEN** a declaration references an actual extant beets item instead of a Spotify export row
- **THEN** the same edition-specific format queue works without creating a Spotify export
- **AND** the queue retains its actual beets parent ID and leaves Spotify ID empty
- **AND** missing, stale, ambiguous or simultaneously supplied parent kinds are refused

#### Scenario: Version or association remains unresolved
- **WHEN** a declaration is unresolved or its owned library metadata does not establish the declared version
- **THEN** unresolved declarations remain visible without being queued, and unclassified owned files do not satisfy a guessed version cell
- **AND** shared IDs or another version's duration/title core do not collapse distinct targets

#### Scenario: Invalid input or preview
- **WHEN** input is malformed, lacks evidence, contradicts its explicit version, has a missing parent or duplicates an edition ID
- **THEN** matching refuses before replacing an existing queue
- **AND** ordinary preview writes no queue/state/report or media, while source fixtures and prepared inputs do not prove acquired four-cell completeness or installed service activation
