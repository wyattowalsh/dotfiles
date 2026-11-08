## Context

Apple Text Replacement is the native store for static phrases. Apple Shortcuts covers menus, dates, and an explicit Expand Anywhere paste. The live library is inventory: promote curated triggers into git, preserve unrelated entries, and keep local contact values in a `0600` overlay. A staged plist is an import candidate, not evidence that Apple accepted it or that iCloud synchronized it.

The compact baseline is 51 base records: 49 public literals plus two local-value references. The ordinary profile adds generated `;help` for 52 desired entries. This is not a required count for arbitrary user exports because unrelated live entries are preserved and a device can be incomplete or divergent.

## Goals / Non-Goals

**Goals**

- One public canonical registry, with a local-only overlay for private values.
- Compact `;` mnemonic triggers, retaining `==+`, `myEn`, and `w4w`; `;panel` stays a recorded browser reservation, while `;pnl` is the panel entry.
- Deterministic, generated help from the effective registry rather than a hand-maintained second phrase list.
- Conflict-aware, lossless where supported, drag-import staging that preserves unrelated entries and captures exact backup bytes.
- Redacted normal output and an explicitly authorized local/private full-reference flow.
- Human-readable Shortcuts recipes and a public-only Shortcut dictionary.

**Non-goals**

- `defaults` or SQLite writes to Apple replacement databases.
- Trigger typing that executes a Shortcut.
- UI automation, automatic device import, automatic deletion, clipboard side effects, or a claim that a generated plist was installed.
- Vendoring harness/MCP configuration, unofficial `.shortcut` compilation, or a generalized template/plugin system.

## Decisions

1. **Default compact profile.** The normal desired profile includes the 51 base entries plus generated `;help` (52). `;help` is a deterministic categorized index describing labels, editable-template/local status, its own entry, and enabled optional reference triggers. It never includes private phrase values. Its public revision includes public phrase bodies and relevant metadata so phrase-only public changes refresh help, without exposing or hashing private values in public output.

2. **Opt-in full-reference profile.** Generated `;hN` pages are off by default. They derive their bodies from enabled base records exactly once, exclude generated help/reference bodies to prevent recursion, and emit a machine-readable page-to-entry manifest. A configurable 1,800-character budget is a layout target, not an asserted Apple limit: entries are whole, never truncated, and an oversized result is reported with a local full-document alternative. Any page containing a resolved private value inherits private sensitivity; generating, staging, or showing it requires deliberate private-output authorization and uses private local files/modes.

3. **Strict canonical model.** Validate the full catalog, including root, retired, reserved, generated-help, and predecessor metadata; reject unknown/missing/mistyped fields, ambiguous/cyclic predecessor ownership, incompatible public/private sources, case-folded collisions, and disabled coverage mistakes. A record has exactly one base phrase source: a public literal or a local-value key. Missing local keys remain unresolved; placeholders are never staged as phrase bodies.

4. **Safe views and CLI contracts.** Listing is metadata-only in text and JSON. `show` outputs byte-exact selected public phrase text and has no misleading JSON mode. Private phrase/references need explicit authorization. `doctor`, Shortcut operations, plan, and stage all use full-catalog validation. Literal `just apple-text` arguments must be forwarded without reinjection into shell source.

5. **Conflict-aware staging.** Plan operations distinguish preserve, safe add, known migration, approved update, unresolved private value, conflict, and reviewed retirement. A trigger match does not authorize overwriting a divergent phrase; additions-only import output cannot resolve conflicts or delete live entries. Parse/render preserves supported wrapper and entry metadata, otherwise rejects an operation that would be lossy. Standalone render refuses the source, symlinks, unrelated existing targets, and produces `0600` output.

6. **Failure-atomic private transaction.** `stage --apply` reads a fixed export snapshot under a lock, retains exact original bytes and a private integrity manifest, then writes/lints artifacts in a unique private temporary transaction. It detects source changes before publication, publishes complete backup/import bundles, cleans partial artifacts on error, and writes the transaction pointer last. State directories are `0700`; overlay, backups, staged plists, private manifests, and private full-reference artifacts are `0600`. Rollback selects the manifest-declared, hash-checked original rather than guessing from directory order.

7. **Native boundary.** Shortcuts consumes only public permitted entries; generated outputs inherit the strictest input sensitivity. Static editable templates remain literal placeholders. `shell_safe` is a routing hint, never permission to execute arbitrary text; help and multiline content are not auto-paste candidates.

## Risks / Trade-offs

- Apple plist exports use multiple schemas. Supported `shortcut`/`phrase`, `replace`/`with`, and known wrappers must retain compatible metadata; ambiguous dual forms or unsupported lossy forms fail rather than guessing.
- Apple import semantics, Text Replacement terminators, device-specific parsing, and iCloud synchronization are operator-observed facts. A fresh export comparison proves only that supplied snapshots match the planned pairs, not real typing or sync behavior.
- Full reference pages can contain local contact values. Keeping them opt-in and private by inheritance prevents generated pages from becoming an indirect public disclosure path.
- Restaging a backup does not remove replacements introduced after the original import. Manual cleanup remains explicitly reviewed after the new triggers are confirmed.
