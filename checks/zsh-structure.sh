#!/usr/bin/env bash
# shellcheck disable=SC2016 # Literal zsh variables are file-match needles.
# Structure gate for zshrc SSOT (CI-safe, file-only).
# Usage: ./checks/zsh-structure.sh [path] [L0|L1|L2|L3|L4|all]
set -euo pipefail

f=${1:-rig/dots/zshrc}
lvl=${2:-all}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
canonical="$ROOT/rig/dots/zshrc"

case "$f" in
  /*) f_abs=$f ;;
  *) f_abs="$PWD/$f" ;;
esac

fail() {
  echo "FAIL(${lvl}): $*" >&2
  exit 1
}

[[ -f $f ]] || fail "missing $f"

if [[ $lvl == L0 || $lvl == all ]]; then
  if grep -Eiq 'amazon-q|Amazon Q|q init zsh' "$f"; then
    fail "Amazon Q present"
  fi
  if grep -Eq 'mise hook-env' "$f"; then
    fail "mise hook-env present"
  fi
fi

if [[ $lvl == L1 || $lvl == all ]]; then
  # Model A: no user-facing compinit in SSOT (OMZ runs one internally)
  if grep -Eiq '(^|[[:space:]])compinit([[:space:]]|$)' "$f"; then
    fail "user compinit present (Model A forbids SSOT compinit)"
  fi
  if ! grep -Eq 'zsh-completions' "$f"; then
    fail "zsh-completions not configured"
  fi
  # fpath block should appear before oh-my-zsh source
  fpath_line=$(grep -n 'fpath=(' "$f" | head -1 | cut -d: -f1 || true)
  omz_line=$(grep -n 'oh-my-zsh.sh' "$f" | head -1 | cut -d: -f1 || true)
  if [[ -n ${fpath_line:-} && -n ${omz_line:-} && $fpath_line -gt $omz_line ]]; then
    fail "fpath configured after oh-my-zsh.sh (must be before)"
  fi
fi

if [[ $lvl == L2 || $lvl == all ]]; then
  plugins_block=$(awk '/plugins=\(/,/^\)/' "$f" 2>/dev/null || true)
  if echo "$plugins_block" | grep -Eq '^[[:space:]]*pyenv[[:space:]]*$'; then
    fail "pyenv plugin present"
  fi
  if echo "$plugins_block" | grep -Eq '^[[:space:]]*poetry(-env)?[[:space:]]*$'; then
    fail "poetry plugin present"
  fi
  if ! grep -Eq 'PNPM_HOME' "$f"; then
    fail "missing PNPM_HOME"
  fi
  if ! grep -Eq 'PIPX_' "$f"; then
    fail "missing PIPX_ env"
  fi
  if ! grep -Eq 'mise activate' "$f"; then
    fail "missing mise activate"
  fi
  if ! grep -Eq 'atuin init zsh --disable-up-arrow --disable-ai' "$f"; then
    fail "missing atuin init (disable-up-arrow --disable-ai)"
  fi
fi

if [[ $lvl == L3 || $lvl == all ]]; then
  last=$(grep -E '^[[:space:]]*(source|builtin source|\.) ' "$f" | grep -v '^[[:space:]]*#' | tail -1 || true)
  if ! echo "$last" | grep -q 'syntax-highlighting'; then
    fail "highlight not last source: ${last:-<none>}"
  fi
fi

# L4 pins the accepted rig contract. `all` applies it to the canonical SSOT;
# explicit L4 is also useful for mutated-copy regression fixtures.
if [[ $lvl == L4 || ($lvl == all && $f_abs == "$canonical") || ${ZSH_STRUCTURE_STRICT:-0} == 1 ]]; then
  expected_plugins=$'git\ngh\nmacos\nvscode\nextract\nsudo\ndocker\nbrew\naws\nterraform\nuv\nzsh-interactive-cd'
  actual_plugins=$(awk '
    /^[[:space:]]*plugins=\(/ { in_plugins=1; next }
    in_plugins && /^[[:space:]]*\)/ { exit }
    in_plugins {
      sub(/#.*/, "")
      gsub(/[[:space:]]/, "")
      if (length($0)) print
    }
  ' "$f")
  [[ $actual_plugins == "$expected_plugins" ]] || fail "approved 12-plugin set/order changed"

  hist_size=$(sed -n 's/^HISTSIZE=\([0-9][0-9]*\)$/\1/p' "$f" | head -1)
  save_hist=$(sed -n 's/^SAVEHIST=\([0-9][0-9]*\)$/\1/p' "$f" | head -1)
  [[ -n $hist_size && -n $save_hist ]] || fail "numeric HISTSIZE/SAVEHIST assignments missing"
  ((10#$hist_size > 10#$save_hist)) || fail "HISTSIZE must remain greater than SAVEHIST"
  for history_opt in hist_reduce_blanks hist_find_no_dups hist_fcntl_lock; do
    grep -Eq "^[[:space:]]*setopt([[:space:]].*)?[[:space:]]${history_opt}([[:space:]]|$)" "$f" \
      || fail "missing history option $history_opt"
  done

  managed_completion_line=$(grep -nF '$HOME/.zsh/completions(N)' "$f" | head -1 | cut -d: -f1 || true)
  omz_line=$(grep -n 'oh-my-zsh.sh' "$f" | head -1 | cut -d: -f1 || true)
  [[ -n $managed_completion_line && -n $omz_line && $managed_completion_line -lt $omz_line ]] \
    || fail "managed completion fpath must precede Oh My Zsh"
  [[ -f $ROOT/rig/home/dot_zsh/completions/_pnpm ]] || fail "tracked _pnpm completion missing"

  if grep -Fq 'ZSH_CUSTOM' "$f"; then
    fail "ZSH_CUSTOM fallback present"
  fi
  if echo "$actual_plugins" | grep -Fxq 'you-should-use'; then
    fail "you-should-use must not consume an OMZ plugin slot"
  fi
  aliases_line=$(grep -nF '.zsh/aliases.zsh' "$f" | head -1 | cut -d: -f1 || true)
  ysu_line=$(grep -nF 'source "$_ysu"' "$f" | head -1 | cut -d: -f1 || true)
  highlight_line=$(grep -nF 'zsh-syntax-highlighting.zsh' "$f" | tail -1 | cut -d: -f1 || true)
  [[ -n $aliases_line && -n $ysu_line && -n $highlight_line ]] || fail "YSU/highlighting source order is incomplete"
  ((aliases_line < ysu_line && ysu_line < highlight_line)) || fail "YSU must load after aliases and before highlighting"
  grep -Fq '$HOMEBREW_PREFIX/share/zsh-you-should-use/you-should-use.plugin.zsh' "$f" \
    || fail "Homebrew you-should-use source missing"
  grep -Fqx 'typeset -ga ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)' "$f" \
    || fail "syntax highlighters must remain main plus brackets"

  if [[ $f_abs == "$canonical" ]]; then
    cmp -s "$canonical" "$ROOT/rig/home/dot_zshrc.tmpl" || fail "zshrc mirror differs from canonical SSOT"
  fi
fi

echo "OK $f $lvl"
