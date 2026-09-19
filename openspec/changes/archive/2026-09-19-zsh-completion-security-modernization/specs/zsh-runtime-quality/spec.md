## ADDED Requirements

### Requirement: Curated plugin set is pinned
The managed shell SHALL load the approved 13-plugin Oh My Zsh set in the documented order, including `colored-man-pages`, and SHALL load Homebrew `zsh-history-substring-search` after `zsh-syntax-highlighting`.

#### Scenario: Shell sources history search
- **WHEN** the Homebrew history-substring-search file exists
- **THEN** zsh sources syntax highlighting first, sources history-substring-search last, enables unique results, and binds common Up/Down escape sequences

#### Scenario: Plugin or source order drifts
- **WHEN** the approved plugin list, highlighter list, history-search source, or Up/Down bindings are removed or reordered incompatibly
- **THEN** the zsh structural contract tests fail

### Requirement: Atuin and history search have distinct key ownership
The runtime SHALL leave Ctrl-R to Atuin and SHALL assign Up/Down history navigation to history-substring-search.

#### Scenario: User searches command history
- **WHEN** the user presses Ctrl-R
- **THEN** Atuin opens its configured search
- **AND WHEN** the user types a substring and presses Up or Down
- **THEN** zsh cycles matching local history entries

### Requirement: Managed command integrations do not append shell initialization
The canonical path and fpath blocks SHALL include Grok and CCS locations without installer-owned trailing blocks.

#### Scenario: Grok and CCS are installed
- **WHEN** a new shell starts with `~/.grok` and `~/.ccs` present
- **THEN** both CLIs are available on PATH and their completion functions are registered through the single Oh My Zsh completion initialization

### Requirement: Startup timing reflects terminal behavior
The repository SHALL provide a report-only startup timing command that accepts a positive run count and reports min, median, and max. On macOS it SHALL allocate a pseudo-terminal before starting interactive zsh.

#### Scenario: Developer measures startup
- **WHEN** `just zsh-time 5` runs on macOS
- **THEN** five pseudo-terminal interactive startups are measured and summarized in milliseconds

#### Scenario: Invalid run count is supplied
- **WHEN** the run count is empty, zero, negative, or non-numeric
- **THEN** the timing helper exits with an actionable validation error

### Requirement: Architectural replacements require evidence
The desired state SHALL NOT activate carapace, fzf-tab, Antidote, or Starship solely from aggregate startup timing.

#### Scenario: Candidate evaluation completes
- **WHEN** a candidate is measured or interactively trialed
- **THEN** documentation records its marginal cost, compatibility concerns, and adopt/defer status
- **AND** Antidote or Starship remains deferred unless targeted profiling identifies the replaced subsystem as the bottleneck
