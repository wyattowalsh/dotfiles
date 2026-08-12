# bad: fpath after oh-my-zsh
export PIPX_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/pipx"
export PIPX_BIN_DIR="$HOME/.local/bin"
export PNPM_HOME="$HOME/Library/pnpm"
plugins=(git uv)
source "$ZSH/oh-my-zsh.sh"
fpath=(
  ${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh/site-functions
  ${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-completions
  $fpath
)
eval "$(mise activate zsh)"
source ${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
