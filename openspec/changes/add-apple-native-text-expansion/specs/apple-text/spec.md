## ADDED Requirements

### Requirement: Apple-native expansion SSOT
The rig SHALL source-control public Text Replacement phrases and Shortcut recipes under `rig/home/private_dot_config/apple-text/`. Merge and staging logic SHALL live in this repository’s `checks/` tree. Private `myaddr` SHALL exist only in a local overlay that is not committed.

#### Scenario: Validate registries
- **WHEN** an operator runs `just apple-text validate`
- **THEN** the command exits 0 when the public JSON and Shortcut recipes are consistent

#### Scenario: Preserve unrelated replacements
- **WHEN** a user-dragged export contains a non-canonical trigger
- **THEN** the merge plan PRESERVEs that entry and does not retire it

#### Scenario: No Apple database writes
- **WHEN** `just apple-text stage --apply` runs
- **THEN** the tool writes backup and staged plist files only and does not modify `TextReplacements.db`
