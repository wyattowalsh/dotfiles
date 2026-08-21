## 1. Defect-First Assurance

- [x] 1.1 Extend `checks/kopia-nightly.sh` with static assertions for the wrapper, per-status timeout, quiet status, single-run lock, launchd progress gate, nonfatal maintenance-only failure, finalizer, and plist timeout keys.
- [x] 1.2 Add offline command stubs and fixtures for success, readiness exhaustion, hung status, snapshot failure, maintenance warning, cleanup failure, TERM, INT, and notification failure.
- [x] 1.3 Run the new fixtures against the current source and record that each intended defect fails for the expected reason.

## 2. Bounded Runner Lifecycle

- [x] 2.1 Add the GNU `gtimeout` public wrapper and private bounded-child dispatch with the strict 43,200-second total ceiling.
- [x] 2.2 Replace function-local trap state with initialized lifecycle state, separate TERM/INT handlers, and one idempotent EXIT finalizer.
- [x] 2.3 Re-disable KopiaUI labels at start and finalization, remove manual caffeinate PID killing, and promote cleanup failure to a nonzero result.
- [x] 2.4 Bound each of eight repository-status attempts and retain the specified backoff schedule with discarded status output.
- [x] 2.5 Centralize exactly-one bounded warning/failure notification and preserve the primary outcome status.
- [x] 2.6 Keep full maintenance after the snapshot loop and make maintenance-only failure a warning with exit zero.

## 3. LaunchAgent And Documentation

- [x] 3.1 Remove plist `TimeOut`, add `ExitTimeOut=120`, and preserve the 04:00 calendar-only launch contract.
- [x] 3.2 Update the backup operator runbook and nested home agent contract for wall-clock, signal, cleanup, notification, and operator-apply behavior.

## 4. Verification

- [x] 4.1 Run shell syntax and the focused offline Kopia check suite.
- [x] 4.2 Run `just check`, `just docs-ci`, `just secrets-scan`, and `just bootstrap --dry-run` without running a live snapshot or installing the LaunchAgent.
- [x] 4.3 Reconcile every requirement and scenario with passing evidence in the OpenSpec change.
