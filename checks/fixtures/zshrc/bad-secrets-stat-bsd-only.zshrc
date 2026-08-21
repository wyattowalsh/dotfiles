# L0: secrets.env gated only with BSD stat -f must fail
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
if [[ -f "$HOME/.zsh/secrets.env" ]]; then
  if [[ "$(/usr/bin/stat -f '%A' "$HOME/.zsh/secrets.env" 2>/dev/null)" == "600" ]]; then
    source "$HOME/.zsh/secrets.env"
  fi
fi
source ${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
