# Amazon Q pre block
[[ -f "${HOME}/Library/Application Support/amazon-q/shell/zshrc.pre.zsh" ]] && source it
export PNPM_HOME=$HOME/Library/pnpm
export PIPX_HOME=$HOME/.local/share/pipx
export PIPX_BIN_DIR=$HOME/.local/bin
fpath=(/opt/homebrew/share/zsh-completions $fpath)
source $ZSH/oh-my-zsh.sh
eval "$(mise activate zsh)"
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
