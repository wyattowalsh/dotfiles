export PNPM_HOME=$HOME/Library/pnpm
export PIPX_HOME=$HOME/.local/share/pipx
export PIPX_BIN_DIR=$HOME/.local/bin
fpath=(/opt/homebrew/share/zsh-completions $fpath)
source $ZSH/oh-my-zsh.sh
compinit
eval "$(mise activate zsh)"
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
