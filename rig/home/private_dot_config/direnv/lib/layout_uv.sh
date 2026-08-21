# shellcheck shell=bash
# uv helpers — activation is routine; synchronization is an explicit opt-in.
# Usage in .envrc: `layout uv`
# Explicit refresh: `layout_uv_sync`, optionally with a Python version/uv flags.

_layout_uv_prepare() {
  watch_file .python-version pyproject.toml uv.lock

  if ! has uv; then
    log_error "uv: command not found. Install from https://docs.astral.sh/uv/"
    return 1
  fi

  if [[ ! -f pyproject.toml ]]; then
    log_error "uv: no pyproject.toml found. Run \`uv init\` to create a project."
    return 1
  fi

  local venv_path
  venv_path="$(expand_path "${UV_PROJECT_ENVIRONMENT:-.venv}")"
  export UV_PROJECT_ENVIRONMENT="$venv_path"
}

_layout_uv_activate() {
  local venv_path="$UV_PROJECT_ENVIRONMENT"

  if [[ ! -d "$venv_path" ]]; then
    log_error "uv: environment not found at $venv_path; run layout_uv_sync explicitly."
    return 1
  fi

  export VIRTUAL_ENV="$venv_path"
  if [[ -d "$venv_path/bin" ]]; then
    PATH_add "$venv_path/bin"
  elif [[ -d "$venv_path/Scripts" ]]; then
    PATH_add "$venv_path/Scripts"
  else
    log_error "uv: environment at $venv_path has no bin directory; run layout_uv_sync explicitly."
    unset VIRTUAL_ENV
    return 1
  fi
}

layout_uv() {
  if (( $# )); then
    log_error "uv: layout uv is activation-only and takes no sync arguments; run layout_uv_sync explicitly."
    return 2
  fi
  _layout_uv_prepare || return
  _layout_uv_activate
}

layout_uv_sync() {
  _layout_uv_prepare || return

  local python_arg=()
  local sync_args=()
  if [[ -n "${1:-}" && "${1:-}" != --* ]]; then
    python_arg=(--python "$1")
    sync_args=("${@:2}")
  else
    sync_args=("$@")
  fi

  uv sync --frozen "${python_arg[@]}" "${sync_args[@]}" || return
  _layout_uv_activate
}
