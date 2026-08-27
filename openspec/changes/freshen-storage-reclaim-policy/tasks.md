## 1. Spec

- [x] 1.1 Proposal, design, and `specs/freshen/spec.md` as in this change
- [x] 1.2 Review-fix delta: row labels, unique-cold polarity, backup timeout, find -P, docker parent dropped

## 2. Tests (RED)

- [x] 2.1 Tighten unique-cold / classified rows / live geometry / catalog / docker-info-fail / tmutil
- [x] 2.2 Stamp helper verifies mtime; skip-newer python3 miss; live warn/err

## 3. Dev-prune

- [x] 3.1 find -P on canonical root; frozen target-root; min_age 10# + cap

## 4. Storage-plan

- [x] 4.1 Drop `~/.docker` parent row
- [x] 4.2 `_run_report_cmd` stdin closed + `FRESHEN_BACKUP_STATUS_TIMEOUT_SEC`

## 5. Docs / version

- [x] 5.1 Help honesty, tmutil, backup timeout, skip-newer not under `-K`
- [x] 5.2 AGENTS.md compare-succeeds wording
- [x] 5.3 mdx + hub one-liner
- [x] 5.4 `freshen-version.sh` fallback + date

## 6. Validate

- [x] 6.1 `just check-freshen`
- [x] 6.2 `just docs-ci` if docs/hub changed
- [x] 6.3 `just secrets-scan`
