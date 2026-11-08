## Why

The nightly runner forces continued traversal after unreadable files. A source
containing unavailable placeholders can consume the shared wall-clock budget
before later roots are attempted. Its retry classifier also searches raw logs
for separate words that can occur in private filenames, incorrectly treating
file-read failures as rclone startup timeouts.

## What Changes

- Use Kopia's native fail-fast behavior for each source, then retain the existing
  loop's attempt of later roots while the shared budget remains.
- Restrict snapshot retries to the native structured rclone startup-timeout
  diagnostic, with the existing three-attempt limit.
- Preserve aggregate failure, maintenance gating, the 43200-second default
  whole-run cap, existing scheduler ownership and terminal-only progress.
- Add isolated fixtures and document the source failure and retry behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `backup`: fail-fast source traversal and diagnostic-specific startup retries.

## Impact

This changes the tracked nightly runner and focused tests. It does not hydrate
files, exclude unreadable paths, add a per-source budget, change the source list,
or create another scheduler. Source validation, approved installation and actual
snapshot coverage remain separate acceptance layers.
