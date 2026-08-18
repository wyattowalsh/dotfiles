#!/usr/bin/env bash
# Locate wyattowalsh/agents and exec its portable bootstrap-dev-env.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Keep identical to agents/scripts/bootstrap-dev-env/locate.sh _is_agents_repo.
_is_agents_repo() {
  local path="$1"
  if [ ! -d "${path}/skills" ]; then
    return 1
  fi
  if [ -f "${path}/agent-bundle.json" ] || [ -f "${path}/AGENTS.md" ]; then
    return 0
  fi
  if [ -d "${path}/agents" ] && [ -f "${path}/pyproject.toml" ]; then
    return 0
  fi
  return 1
}

find_agents_root() {
  local candidate parent
  if [ -n "${WAGENTS_REPO_ROOT:-}" ] && _is_agents_repo "${WAGENTS_REPO_ROOT}"; then
    (cd "${WAGENTS_REPO_ROOT}" && pwd)
    return 0
  fi
  for candidate in "${HOME}/dev/projects/agents" "${HOME}/dev/tools/agents"; do
    if _is_agents_repo "$candidate"; then
      (cd "$candidate" && pwd)
      return 0
    fi
  done
  parent="$(cd "${REPO_ROOT}/.." && pwd)"
  if _is_agents_repo "${parent}/agents"; then
    (cd "${parent}/agents" && pwd)
    return 0
  fi
  return 1
}

main() {
  local root installer
  if ! root="$(find_agents_root)"; then
    printf 'agents checkout not found.\n' >&2
    printf 'Clone https://github.com/wyattowalsh/agents.git to ~/dev/projects/agents\n' >&2
    printf 'or set WAGENTS_REPO_ROOT, then re-run: just bootstrap-dev --dry-run\n' >&2
    exit 1
  fi
  installer="${root}/scripts/bootstrap-dev-env.sh"
  if [ ! -f "$installer" ]; then
    printf 'Missing %s\n' "$installer" >&2
    printf 'Pull the latest wyattowalsh/agents (bootstrap-dev-env.sh).\n' >&2
    exit 1
  fi
  exec bash "$installer" "$@"
}

main "$@"
