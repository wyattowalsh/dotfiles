## Context

The nightly runner is a user LaunchAgent that snapshots an explicit source list after a sleeping Mac becomes available. Launchd no longer implements the plist `TimeOut` key as a job wall-clock limit. The current EXIT trap closes over a function-local `caffeine_pid`, handles TERM/INT as cleanup-only events, and can exit before re-disabling KopiaUI login labels. Repository readiness probes also have no per-attempt limit, and early `die` paths bypass notification.

The design must be testable without contacting the real Kopia repository, mutating launchd, or posting real notifications.

Review traceability:

| Finding | Contract |
| --- | --- |
| RV-S-001 | Initialized lifecycle state, signal-specific exits, and one idempotent finalizer |
| RV-S-003 | Strict whole-run and per-status-command timeouts |
| RV-S-004 | Centralized exactly-one notification for early and late terminal outcomes |
| RV-S-005 | Static assertions plus an offline behavior matrix |

## Goals / Non-Goals

**Goals:**

- Bound every normal nightly run to twelve hours, including termination grace.
- Make signal, finalizer, cleanup, maintenance, notification, and exit-code behavior deterministic.
- Bound repository readiness probes and preserve the established retry policy.
- Preserve explicit-source snapshots, single-run locking, launchd progress suppression, and secret hygiene.
- Prove the contract with offline command stubs and static assertions.

**Non-Goals:**

- Guarantee cleanup after SIGKILL, kernel panic, or power loss.
- Change snapshot sources, retention, ignores, repository credentials, or rclone remotes.
- Run a real snapshot, install/reload a LaunchAgent, or notify the desktop during tests.

## Decisions

### Bound the process outside its mutable work

The public entrypoint wraps only a normal live run with fixed Homebrew GNU `gtimeout`:

```text
/opt/homebrew/bin/gtimeout --verbose --signal=TERM --kill-after=60s 43140s <runner> __bounded-run
```

The TERM threshold plus KILL grace equals the strict 43,200-second ceiling. `install`, `doctor`, `--dry-run`, and the private child mode bypass the wrapper. The LaunchAgent removes the unimplemented `TimeOut` key and uses `ExitTimeOut=120` solely as launchd termination grace.

Alternatives rejected: trusting launchd `TimeOut` (not implemented), an internal elapsed-time loop (cannot stop a blocked child reliably), and an unbounded TERM grace (not a strict ceiling).

### Use one initialized lifecycle state and one finalizer

Lifecycle state is initialized outside the work function. TERM and INT handlers record their outcome and exit 143 or 130. One idempotent EXIT finalizer clears traps, re-disables both KopiaUI labels before other cleanup, validates/removes temporary state, computes the final outcome, and emits at most one notification.

`caffeinate -w $$` follows the runner PID, so the finalizer does not kill a recorded caffeinate PID. This avoids both out-of-scope state and PID-reuse hazards. Re-disabling the labels at both start and finalization is the best-effort mitigation for uncatchable termination.

Alternatives rejected: a shared `trap cleanup EXIT TERM INT` (signals may continue execution and recurse into cleanup), function-local trap state, and explicit caffeinate killing.

### Treat cleanup and maintenance as different outcome classes

Snapshot, readiness, lifecycle, signal, and cleanup failures are operational failures and exit nonzero. Cleanup failure promotes an otherwise successful run to failure. A maintenance-only failure produces one warning but leaves successful snapshots at exit zero. Combined failures produce one combined failure notification rather than multiple alerts.

Notifications use static, secret-free text, are independently bounded to approximately ten seconds, and never replace the primary exit status.

### Bound readiness probes independently

Run no more than eight repository-status attempts. Each attempt receives TERM at 30 seconds and KILL five seconds later, discards output, and treats timeout as a normal failed attempt. Delays after failed attempts are `5, 10, 20, 30, 30, 30, 30` seconds. Exhaustion is an operational failure.

### Test through injected commands

Offline tests place stubs for Kopia, launchctl, osascript, rclone, caffeinate, and related commands ahead of the runner PATH. Fixtures record argv and ordered lifecycle events without exposing secret values. Signal tests target only disposable test subprocesses. Static checks retain prohibitions on `--all`, direct `$HOME` snapshots, absolute user paths, and secret-shaped values.

## Risks / Trade-offs

- **Hard KILL cannot run cleanup** → Disable KopiaUI labels at run start and keep the KILL grace explicit.
- **Homebrew prefix is Apple-Silicon-specific** → This repository targets the `w4w-mbp` Apple Silicon rig and already declares GNU coreutils.
- **Notification infrastructure can hang or fail** → Bound it and ignore only its status while retaining the primary outcome.
- **Stub drift can create false confidence** → Pair functional stubs with static contract assertions and retain a separately gated operator `doctor` check.
- **Concurrent runner invocations can race** → Preserve the single-run lock and pin it in tests.

## Migration Plan

1. Land defect-first offline checks.
2. Update the runner and plist together so wrapper and launchd semantics cannot diverge.
3. Update the operator runbook and nested home contract.
4. Run focused checks, aggregate checks, docs CI, and secrets scan.
5. Leave `kopia-nightly install`, LaunchAgent reload, and live snapshot execution for an explicit operator action.

Rollback restores the prior runner and plist together. No repository data migration is required.

## Open Questions

None. Timeout, signal, cleanup, maintenance, and notification semantics are fixed by this change.
