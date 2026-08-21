# good-minimal: legal skeleton for structure gate
export PIPX_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/pipx"
export PIPX_BIN_DIR="$HOME/.local/bin"
export PNPM_HOME="$HOME/Library/pnpm"
fpath=(
  ${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh/site-functions
  ${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-completions
  $fpath
)
plugins=(git uv)
source "$ZSH/oh-my-zsh.sh"
eval "$(mise activate zsh)"
if command -v atuin &>/dev/null; then
  eval "$(atuin init zsh --disable-up-arrow --disable-ai)"
fi
source ${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
