# bad: no pipx environment variables
export PNPM_HOME="$HOME/Library/pnpm"
fpath=(
  ${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh/site-functions
  ${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-completions
  $fpath
)
plugins=(git uv)
source "$ZSH/oh-my-zsh.sh"
eval "$(mise activate zsh)"
source ${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
