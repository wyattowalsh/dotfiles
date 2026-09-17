## ADDED Requirements

### Requirement: Live dashboard is a two-pane framed board
On an interactive TTY with `--progress=auto` or `--progress=live` (and not `plain`), the live dashboard SHALL paint a rounded box containing a PHASES rail of all phases and a NOW pane for the in-flight lane (name, optional package, truncated last child line, elapsed). It SHALL NOT be solely seven unboxed `icon Phase: status` lines.

#### Scenario: Live dump is a dashboard
- **WHEN** `freshen` runs with live enabled under test (`FRESHEN_FORCE_LIVE=1` and `FRESHEN_UNDER_TEST` set)
- **THEN** stdout includes the labels `PHASES` and `NOW` and a rounded box drawing character

#### Scenario: Live dump is not the old seven-row list
- **WHEN** the same live run is captured
- **THEN** the dump is not only the previous unboxed seven-row phase list

### Requirement: NOW includes a discovery progress graph
After inventory discovers outdated formulae, casks, or apps, the NOW pane SHALL render an OVERALL graph that fans out from inventory into per-package nodes for those lanes and merges into cleanup → caches → doctor. Node count SHALL grow with discovered packages.

#### Scenario: Discovered cask and formula become graph nodes
- **WHEN** a live dry-run inventories outdated `wget` and `firefox`
- **THEN** stdout includes `OVERALL` plus those package names as graph nodes

### Requirement: Recap reuses live chrome
After live closes, a non-dry-run recap SHALL use the same outer rounded box, with Attention and Next actions before the phase Summary. Honesty status words SHALL remain the existing tokens.

#### Scenario: Degraded apply recap is boxed
- **WHEN** a degraded apply run used live
- **THEN** the recap region after the last alt-screen leave includes the box and Attention-first order

### Requirement: plain is not the dashboard
`--progress=plain` (and `FRESHEN_LOW_POWER=1`) SHALL NOT emit box drawing or live pane labels.

#### Scenario: plain apply has no dashboard chrome
- **WHEN** `freshen --progress=plain --no-color --yes` runs under test
- **THEN** stdout contains no `╭` and no `PHASES`/`NOW` pane chrome

### Requirement: Busy lock offers replace
When another live freshen holds the instance lock, an interactive run SHALL list the holder and offer to take the lock. `--replace` SHALL take the lock without a TTY. A login shell holder SHALL NOT be SIGKILL'd.

#### Scenario: Non-interactive lock stays blocked
- **WHEN** a second non-interactive freshen hits a live lock
- **THEN** it exits non-zero and points at a TTY or `--replace`
