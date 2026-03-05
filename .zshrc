export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

if [[ -r "${XDG_CACHE_HOME}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export LANG="${LANG:-en_US.UTF-8}"
export EDITOR="${EDITOR:-code --wait}"
export PAGER="${PAGER:-less}"
export LESS="${LESS:--FRX}"

typeset -U path fpath

path=(
  "$HOME/.local/bin"
  "$HOME/go/bin"
  "$HOME/bin"
  $path
)
export PATH

fpath=(
  "$XDG_DATA_HOME/zsh/site-functions"
  "$HOME/.zsh/completions"
  $fpath
)

export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
  git
  git-commit
  gitignore
  gh
  docker
  docker-compose
  aws
  terraform
  bun
  npm
  pip
  python
  poetry
  poetry-env
  uv
  vscode
  aliases
  colored-man-pages
  colorize
  copyfile
  copypath
  encode64
  history
  jsontools
  safe-paste
  zsh-autosuggestions
  zsh-syntax-highlighting
)

if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
fi

if [[ -r "$HOME/.p10k.zsh" ]]; then
  source "$HOME/.p10k.zsh"
fi

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

_nvm_lazy_load() {
  unset -f nvm node npm npx
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
}

node() {
  _nvm_lazy_load
  command node "$@"
}

npm() {
  _nvm_lazy_load
  command npm "$@"
}

npx() {
  _nvm_lazy_load
  command npx "$@"
}

nvm() {
  _nvm_lazy_load
  nvm "$@"
}

_fd_cmd='fd'
if command -v fd >/dev/null 2>&1; then
  :
elif command -v fdfind >/dev/null 2>&1; then
  alias fd='fdfind'
  alias fdf='fdfind'
  _fd_cmd='fdfind'
else
  _fd_cmd='find'
fi

if [[ "$_fd_cmd" == 'find' ]]; then
  export FZF_DEFAULT_COMMAND='find . -type f -not -path "*/.git/*"'
  export FZF_ALT_C_COMMAND='find . -type d -not -path "*/.git/*"'
else
  export FZF_DEFAULT_COMMAND="${_fd_cmd} --type f --hidden --follow --exclude .git"
  export FZF_ALT_C_COMMAND="${_fd_cmd} --type d --hidden --follow --exclude .git"
fi
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:---height=40% --layout=reverse --border}"

if [[ -r "$HOME/.fzf.zsh" ]]; then
  source "$HOME/.fzf.zsh"
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi

if command -v rbenv >/dev/null 2>&1; then
  eval "$(rbenv init - zsh)"
fi

if command -v eza >/dev/null 2>&1; then
  alias ls='eza --group-directories-first --icons=auto'
  alias ll='eza -lah --group-directories-first --icons=auto'
  alias la='eza -a --group-directories-first --icons=auto'
else
  alias ll='ls -alF'
  alias la='ls -A'
fi

if command -v bat >/dev/null 2>&1; then
  alias cat='bat --paging=never'
elif command -v batcat >/dev/null 2>&1; then
  alias bat='batcat'
  alias cat='batcat --paging=never'
fi

if command -v lazygit >/dev/null 2>&1; then
  alias lg='lazygit'
fi

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'

alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'

y() {
  local tmp cwd
  tmp="$(mktemp -t yazi-cwd.XXXXXX)"
  yazi "$@" --cwd-file="$tmp"
  if [[ -f "$tmp" ]]; then
    cwd="$(<"$tmp")"
    if [[ -n "$cwd" && "$cwd" != "$PWD" ]]; then
      builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
  fi
}

if [[ "${TERM_PROGRAM:-}" == "vscode" ]] && command -v code >/dev/null 2>&1; then
  _vscode_shell_integration="$(code --locate-shell-integration-path zsh 2>/dev/null)"
  if [[ -n "$_vscode_shell_integration" && -r "$_vscode_shell_integration" ]]; then
    source "$_vscode_shell_integration"
  fi
  unset _vscode_shell_integration
fi

if [[ -n "${CODESPACES:-}" ]]; then
  export CODESPACES_ENV=true
fi

if [[ -r "$HOME/.zshrc.local" ]]; then
  source "$HOME/.zshrc.local"
fi
