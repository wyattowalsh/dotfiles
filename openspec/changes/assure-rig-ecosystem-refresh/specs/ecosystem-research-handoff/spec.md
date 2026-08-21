## ADDED Requirements

### Requirement: AI research capability has one external source of truth

The `rig-ecosystem-refresh` skill and `rig-ecosystem-index` workflow SHALL be owned by `wyattowalsh/agents`, not by this dotfiles repository.

#### Scenario: Dotfiles source tree after handoff

- **WHEN** the agents-owned replacement has passed source and local-projection validation
- **THEN** `.grok/workflows/rig-ecosystem-refresh.rhai` is absent from tracked or untracked dotfiles workflow discovery paths
- **AND** this repository contains no replacement AI client manifest, MCP configuration, or harness configuration

#### Scenario: Research artifacts are retained

- **WHEN** an ecosystem index writes reusable run artifacts for this repository
- **THEN** they live only beneath ignored `local/rig-ecosystem/` or host scratch state
- **AND** secret values and raw private inventory are not promoted to tracked files

### Requirement: Pre-approval ecosystem indexing is read-only

Surface discovery, catalog enumeration, documentation inventory, dossier synthesis, reconciliation, audit, and recommendation work SHALL use read-only workers and SHALL NOT mutate tracked desired state or the live rig.

#### Scenario: Indexing begins

- **WHEN** `rig-ecosystem-refresh index` or `resume` runs before approval
- **THEN** every research child receives read-only capability
- **AND** package install, Chezmoi apply, nix-darwin apply, LaunchAgent mutation, live backup execution, commit, and push remain disabled

### Requirement: Exhaustiveness is count-reconciled

An ecosystem run SHALL claim exhaustive completion only after dynamically discovered surfaces, authoritative catalog items, and the defined current first-party documentation universe reconcile with no failed, pending, or stale identifiers.

#### Scenario: Complete run

- **WHEN** every discovered surface and catalog item has a stable identifier and dossier
- **AND** every enumerated current documentation page is accounted for
- **AND** final catalog revalidation finds no drift
- **THEN** `status` may be `complete`
- **AND** the run may mark its board approval-eligible

#### Scenario: Work remains or evidence is stale

- **WHEN** any surface, item, or documentation page is failed, pending, omitted, or stale
- **THEN** the result is `partial`, `blocked`, or `failed`
- **AND** it lists exact unresolved identifiers and a continuation manifest when retry is possible
- **AND** it does not claim exhaustive coverage or solicit integration approval

### Requirement: Integration is digest- and approval-bound

Tracked integration SHALL occur only for exact recommendations explicitly approved against unchanged evidence and target state.

#### Scenario: Approved integration

- **WHEN** a complete board digest, exact stable recommendation IDs, and target-file hashes match the current request and workspace
- **AND** the user explicitly approves those IDs
- **THEN** integration may edit only the named targets

#### Scenario: Approval or state does not match

- **WHEN** the board is partial/stale, its digest differs, a recommendation ID is absent, approval is missing, or a target hash changed
- **THEN** integration fails closed without tracked or live-state mutation

### Requirement: Legacy workflow migration is recoverable and collision-free

Recognized legacy workflow copies SHALL be archived outside workflow discovery roots only after the replacement source and local projection validate.

#### Scenario: Recognized legacy copies

- **WHEN** the project and user legacy workflow bytes match SHA-256 `7baef71b8dff635005fb09022cdf2010aa72e220de46c4dba8be7c35f3bd0c66`
- **AND** the canonical and projected `rig-ecosystem-index` workflow bytes match
- **THEN** each legacy copy may be moved to a recoverable non-discovery archive
- **AND** the archive hash is verified before the original is removed

#### Scenario: Destination or legacy copy diverges

- **WHEN** a replacement destination or legacy workflow has unexpected bytes
- **THEN** migration stops without overwriting, deleting, or silently duplicating either version

#### Scenario: Local capability is inspected

- **WHEN** the locally projected replacement is inspected from this repository
- **THEN** exactly one unqualified `rig-ecosystem-refresh` skill is visible
- **AND** it reports no collision
- **AND** the installed workflow matches the canonical agents-owned source
