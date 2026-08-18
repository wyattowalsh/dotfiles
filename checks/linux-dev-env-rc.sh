#!/usr/bin/env bash
# just check-linux-dev-env-rc
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINUX_SH="$ROOT/rig/bootstrap/linux.sh"

fail=0

fail_msg() {
  printf 'linux-dev-env-rc: %s\n' "$*" >&2
  fail=1
}

if [ ! -f "$LINUX_SH" ]; then
  printf 'linux-dev-env-rc: missing %s\n' "$LINUX_SH" >&2
  exit 1
fi

if ! awk '/^run_dev_env[[:space:]]*\(/,/^}/' "$LINUX_SH" | grep -Eq '^[[:space:]]*set \+e[[:space:]]*$'; then
  fail_msg "run_dev_env must capture wrapper status with set +e"
fi
if awk '/^run_dev_env[[:space:]]*\(/,/^}/' "$LINUX_SH" | grep -Eq 'if[[:space:]]+bash "\$wrapper"'; then
  fail_msg "run_dev_env must not use if bash \"\$wrapper\"; then ...; fi; rc=\$?"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME"

MOCK_WRAPPER="$TMP/dev-env.sh"
cat > "$MOCK_WRAPPER" <<'EOF'
#!/usr/bin/env bash
# Mock agents wrapper: always fail so rc-capture is observable.
exit 7
EOF
chmod +x "$MOCK_WRAPPER"

FIXTURE="$TMP/rc-capture.bash"
cat > "$FIXTURE" <<'EOF'
# Mirrors rig/bootstrap/linux.sh run_dev_env rc capture.
run_wrapper_with_captured_rc() {
  local wrapper="$1"
  local rc=0
  set +e
  bash "$wrapper"
  rc=$?
  set -e
  return "$rc"
}
EOF

# shellcheck disable=SC1090
source "$FIXTURE"

set +e
run_wrapper_with_captured_rc "$MOCK_WRAPPER"
fixture_rc=$?
set -e
if [ "$fixture_rc" -eq 0 ]; then
  fail_msg "fixture capture returned 0 for a wrapper that exits 7"
elif [ "$fixture_rc" -ne 7 ]; then
  fail_msg "fixture capture expected 7, got ${fixture_rc}"
fi

# The buggy `if cmd; then; fi; rc=$?` pattern hides a failed command.
set +e
if bash "$MOCK_WRAPPER"; then
  :
fi
buggy_rc=$?
set -e
if [ "$buggy_rc" -ne 0 ]; then
  fail_msg "expected if/fi; rc=\$? to be 0 after a failed command (got ${buggy_rc})"
fi

REAL_HOME="${HOME}"
HOME="$FAKE_HOME"
# shellcheck disable=SC1090
source "$LINUX_SH"

if [ -e "$FAKE_HOME/.zshrc" ]; then
  fail_msg "sourcing linux.sh must not create HOME dotfiles"
fi

DEV_ENV_WRAPPER="$MOCK_WRAPPER"
if [ "$DEV_ENV_WRAPPER" = "$ROOT/rig/bootstrap/dev-env.sh" ]; then
  printf 'linux-dev-env-rc: refusing to invoke the real dev-env wrapper\n' >&2
  exit 1
fi

SMOKE_CHECK=0
VERBOSE=0
ERRORS=0
WARNINGS=0
ACTIONS_RUN=0
ACTIONS_SKIPPED=0

DRY_RUN=1
set +e
run_dev_env
dry_rc=$?
set -e
if [ "$dry_rc" -ne 0 ]; then
  fail_msg "dry-run path must continue after wrapper failure (rc=${dry_rc})"
fi

ERRORS=0
WARNINGS=0
DRY_RUN=0
set +e
run_dev_env
apply_rc=$?
set -e
if [ "$apply_rc" -eq 0 ]; then
  fail_msg "apply-style path must return nonzero after wrapper failure"
fi

if [ -e "$FAKE_HOME/.zshrc" ] || [ -e "$FAKE_HOME/.oh-my-zsh" ]; then
  fail_msg "check mutated fake HOME"
fi

HOME="$REAL_HOME"

if [ "$fail" -ne 0 ]; then
  exit 1
fi
printf 'linux-dev-env-rc: ok\n'
