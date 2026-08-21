## ADDED Requirements

### Requirement: Docs Hub Single Source Of Truth

Operator hub content for landing cards and the docs index hub SHALL be derived from `docs/lib/hub-manifest.json` (via `docs/lib/sections.ts` and `DocsHub`). Sidebar order SHALL remain defined in `docs/content/docs/meta.json`.

#### Scenario: Landing and index share hub data

- **WHEN** hub content is rendered on `/` or `/docs`
- **THEN** card and hub-table rows are derived from `docs/lib/hub-manifest.json`
- **AND** sidebar page order remains defined in `docs/content/docs/meta.json`
- **AND** hand-maintained competing path tables are not used on the docs index

#### Scenario: Hub parity gate

- **WHEN** `just docs-hub-parity` (or `just docs-ci`) is run
- **THEN** the set of non-index content pages in `meta.json` equals the set of slugs in `hub-manifest.json`

### Requirement: Operator Docs Location

Human operator runbooks SHALL live under `docs/content/docs/`. Nested `AGENTS.md` files MAY remain as agent-runtime contracts and SHALL NOT replace operator runbooks.

#### Scenario: No parallel topics tree

- **WHEN** operator runbooks are maintained
- **THEN** they live under `docs/content/docs/`
- **AND** a `topics/` operator-documentation tree is not used as a parallel human runbook surface

### Requirement: Docs Validation Gate

Documentation changes SHALL be validatable through `just docs-ci`.

#### Scenario: docs-ci

- **WHEN** `just docs-ci` is run
- **THEN** frozen dependency install, docs typecheck, docs production build, docs-sensitive scanning, and docs-hub-parity succeed

### Requirement: Docs Secrets And Host Identity Hygiene

Documentation SHALL avoid secret values and free-prose host identity leakage.

#### Scenario: Names only and limited host alias

- **WHEN** documentation mentions credentials or hosts
- **THEN** environment variables appear as names only
- **AND** host flake aliases appear only in fenced commands or required path cells
- **AND** free prose of the form `on <host-alias>` is not used

### Requirement: Thin Subsystem READMEs

Subsystem README files MAY exist when they are short and non-authoritative.

#### Scenario: Non-authoritative brew README

- **WHEN** `rig/brew/README.md` (or a similar subsystem README) exists
- **THEN** it does not replace `docs/content/docs/*` as the operator runbook SSOT
- **AND** it only summarizes commands and points to docs pages and nested `AGENTS.md`

#### Scenario: No parallel human runbook tree

- **WHEN** human-facing documentation is added
- **THEN** it is not reintroduced under `topics/` or vendor root stubs such as `GEMINI.md`
