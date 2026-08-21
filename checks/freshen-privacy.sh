#!/usr/bin/env bash
# Publish hygiene for freshen: fail on absolute home paths in tracked artifacts,
# and on secret-shaped strings in fixtures/goldens (not redaction unit tests).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${REPO_DIR}/rig/home/dot_zsh/functions"
FRESHEN_FILE="${ROOT}/freshen"
TEST_DIR="${ROOT}/tests"
FIXTURES_DIR="${TEST_DIR}/fixtures"

if [[ ! -r "$FRESHEN_FILE" ]]; then
  printf 'freshen-privacy: missing freshen at %s\n' "$FRESHEN_FILE" >&2
  exit 1
fi

failures=0

collect_files() {
  local dir="$1"
  shift
  if [[ ! -d "$dir" ]]; then
    return 0
  fi
  find "$dir" -type f "$@" -print 2>/dev/null || true
}

# --- Absolute home paths: never publish in freshen sources/tests/fixtures ---
path_targets=("$FRESHEN_FILE")
while IFS= read -r f; do
  [[ -n "$f" ]] && path_targets+=("$f")
done < <(collect_files "$TEST_DIR" \( -name '*.zsh' -o -name '*.txt' -o -name '*.md' -o -name '*.log' -o -name '*.golden' \))

path_patterns=('/Users/' '/home/')
for pattern in "${path_patterns[@]}"; do
  hits=""
  if command -v rg >/dev/null 2>&1; then
    hits="$(rg -n -F -- "$pattern" "${path_targets[@]}" 2>/dev/null || true)"
  else
    hits="$(grep -RsnF -- "$pattern" "${path_targets[@]}" 2>/dev/null || true)"
  fi
  if [[ -n "$hits" ]]; then
    printf 'freshen-privacy: absolute home path pattern %q found:\n%s\n' "$pattern" "$hits" >&2
    failures=$((failures + 1))
  fi
done

# --- Secret-shaped strings: fixtures/goldens only (tests may inject fakes to assert redaction) ---
secret_targets=()
while IFS= read -r f; do
  [[ -n "$f" ]] && secret_targets+=("$f")
done < <(collect_files "$FIXTURES_DIR" \( -name '*.txt' -o -name '*.log' -o -name '*.md' -o -name '*.zsh' -o -name '*.golden' \))
# Also scan any *.golden under tests/
while IFS= read -r f; do
  [[ -n "$f" ]] && secret_targets+=("$f")
done < <(collect_files "$TEST_DIR" -name '*.golden')

if ((${#secret_targets[@]} > 0)); then
  secret_patterns=(
    'password='
    'PASSWORD='
    'Bearer '
    'api_key='
    'api-key='
    'x-api-key='
    'Authorization: '
    'authorization: '
  )
  for pattern in "${secret_patterns[@]}"; do
    hits=""
    if command -v rg >/dev/null 2>&1; then
      hits="$(rg -n -F -- "$pattern" "${secret_targets[@]}" 2>/dev/null || true)"
    else
      hits="$(grep -RsnF -- "$pattern" "${secret_targets[@]}" 2>/dev/null || true)"
    fi
    if [[ -n "$hits" ]]; then
      printf 'freshen-privacy: secret-shaped pattern %q in fixtures/goldens:\n%s\n' "$pattern" "$hits" >&2
      failures=$((failures + 1))
    fi
  done
fi

# Help/code must document XDG log path honesty (placeholder form).
if ! grep -Fq 'XDG_STATE_HOME' "$FRESHEN_FILE"; then
  printf 'freshen-privacy: freshen must mention XDG_STATE_HOME for log path honesty\n' >&2
  failures=$((failures + 1))
fi

if ((failures > 0)); then
  printf 'freshen-privacy: %d privacy check(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'freshen privacy publish checks OK\n'
