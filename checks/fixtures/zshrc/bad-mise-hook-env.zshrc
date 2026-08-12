# bad: mise hook-env present
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
eval "$(mise hook-env -s zsh)"
source ${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
