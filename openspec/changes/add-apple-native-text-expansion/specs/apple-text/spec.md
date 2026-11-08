## ADDED Requirements

### Requirement: Apple-native expansion SSOT
The rig SHALL source-control public Text Replacement phrases and Shortcut recipes under `rig/home/private_dot_config/apple-text/`. Merge, help generation, validation, and staging logic SHALL live in this repository’s `checks/` tree. Private address and phone values SHALL exist only in a local overlay that is not committed.

#### Scenario: Validate registries
- **WHEN** an operator runs `just apple-text validate`
- **THEN** the command exits 0 only when the complete public catalog, local overlay values that are present, generated-help configuration, and Shortcut recipes are structurally consistent

#### Scenario: Preserve unrelated replacements
- **WHEN** a user-dragged export contains a non-canonical trigger
- **THEN** the merge plan PRESERVEs that entry and does not retire or overwrite it

#### Scenario: No Apple database writes
- **WHEN** `just apple-text stage --apply` runs
- **THEN** the tool writes only local backups and staged plist/manifest artifacts and does not modify `TextReplacements.db` or `NSGlobalDomain` replacement keys

### Requirement: Compact desired profile and generated help
The default desired profile SHALL comprise 51 base records plus a generated `;help` entry, for 52 desired entries in the supplied baseline. This desired count SHALL be reported separately from the number of entries found in a user export or live library.

#### Scenario: Render compact help
- **WHEN** an operator renders or stages the default profile
- **THEN** `;help` is generated deterministically from enabled effective base records, includes descriptive self-entry information, and exposes labels/status rather than phrase bodies

#### Scenario: Update public help revision
- **WHEN** an enabled public canonical phrase body or help-relevant metadata changes
- **THEN** the generated help revision changes without using private phrase values or private-value hashes in public output

#### Scenario: Unresolved local value
- **WHEN** a required local overlay key is missing
- **THEN** planning reports the value as unresolved and staging does not substitute a placeholder phrase body

### Requirement: Opt-in private full references
The implementation SHALL offer an explicit full-reference profile that generates numbered `;hN` pages from base records. This profile SHALL be disabled by default.

#### Scenario: Generate full references
- **WHEN** an operator explicitly enables the full-reference profile and required values are resolved
- **THEN** every enabled base phrase occurs exactly once across generated reference pages, generated help/reference pages are not recursively embedded, and a page-to-entry manifest is available for verification

#### Scenario: Private reference inheritance
- **WHEN** a reference page includes a resolved private base phrase
- **THEN** the page and related guide/manifest are treated as private and require explicit private-output authorization; their text SHALL NOT enter public docs, normal JSON, or the public Shortcut dictionary

#### Scenario: Oversized reference content
- **WHEN** a whole entry would exceed the configured reference-page budget
- **THEN** the system reports the condition and does not truncate the phrase or assert that the budget is an Apple platform limit

### Requirement: Redacted and exact output modes
Normal operational output SHALL not disclose private values. Listing SHALL be metadata-only, and exact phrase output SHALL be an explicit selected-record operation.

#### Scenario: List records
- **WHEN** an operator runs the list command in text or JSON format
- **THEN** the output contains metadata only and no phrase bodies

#### Scenario: Show a public phrase
- **WHEN** an operator explicitly shows a public trigger
- **THEN** the command emits the selected phrase byte-for-byte without an appended newline or phrase evaluation

#### Scenario: Private output gating
- **WHEN** a command would emit resolved private content
- **THEN** it requires explicit private-output authorization and otherwise returns a redacted status

### Requirement: Lossless, failure-atomic staging
The staging implementation SHALL preserve supported plist wrapper and per-entry metadata, reject unsupported lossy forms, retain exact source backup bytes, and publish private artifacts atomically.

#### Scenario: Detect a conflict
- **WHEN** an export has a canonical or predecessor trigger with a divergent phrase
- **THEN** the plan records a redacted conflict and does not silently overwrite it in an additions-only import

#### Scenario: Publish a stage transaction
- **WHEN** `stage --apply` processes a valid unchanged source export
- **THEN** it creates mode-`0700` state directories and mode-`0600` private artifacts in a unique transaction, validates all artifacts before publication, and updates the transaction pointer only after a complete bundle is published

#### Scenario: Staging failure
- **WHEN** rendering, linting, or source-stability verification fails during staging
- **THEN** the implementation leaves no completed transaction pointer or partial published transaction and reports the failure without leaking private phrase values

#### Scenario: Restage a rollback
- **WHEN** an operator requests rollback from a staged transaction
- **THEN** the tool selects the transaction-manifest-declared, hash-checked original export and makes a reviewable local restage; it does not claim that later live entries are deleted

### Requirement: Manual import and verification boundary
Apple Text Replacement import, typed expansion behavior, iCloud synchronization, clipboard behavior, and device behavior SHALL remain manual and separately observed actions.

#### Scenario: Stage an import candidate
- **WHEN** staging completes
- **THEN** the output directs the operator to manually drag the staged plist into Text Replacements and does not claim installation, live deletion, or device verification

#### Scenario: Compare a post-import export
- **WHEN** an operator supplies a fresh export to `verify-export`
- **THEN** the result reports missing, divergent, and unexpected planned pairs redacted and describes only the supplied snapshot comparison, not typing behavior or iCloud synchronization
