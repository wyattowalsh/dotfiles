# Amazon Q pre block. Keep at the top of this file.
[[ -f "${HOME}/Library/Application Support/amazon-q/shell/zshrc.pre.zsh" ]] && builtin source "${HOME}/Library/Application Support/amazon-q/shell/zshrc.pre.zsh"

# ═══════════════════════════════════════════════════════════════════════════════
# ~/.zshrc — Optimized Configuration
# ═══════════════════════════════════════════════════════════════════════════════
# Features:
#   • Lazy-loaded NVM (~200ms startup savings)
#   • Deduplicated PATH/fpath with typeset -U
#   • Guarded Homebrew integrations
#   • Modular secrets management
#   • Streamlined plugin set
#   • CLI power tools (ripgrep, fd, fzf, bat, delta, eza)
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# Powerlevel10k Instant Prompt (MUST remain near top, before any console output)
# https://github.com/romkatv/powerlevel10k#instant-prompt
# ───────────────────────────────────────────────────────────────────────────────
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ───────────────────────────────────────────────────────────────────────────────
# Deduplication (set early, before any path modifications)
# ───────────────────────────────────────────────────────────────────────────────
typeset -U path fpath manpath

# ───────────────────────────────────────────────────────────────────────────────
# Homebrew Detection & Prefix Resolution
# ───────────────────────────────────────────────────────────────────────────────
if [[ -z "$HOMEBREW_PREFIX" ]]; then
    if [[ -x /opt/homebrew/bin/brew ]]; then
        # Apple Silicon
        export HOMEBREW_PREFIX="/opt/homebrew"
    elif [[ -x /usr/local/bin/brew ]]; then
        # Intel Mac
        export HOMEBREW_PREFIX="/usr/local"
    elif command -v brew &>/dev/null; then
        # Fallback: ask brew (slower)
        export HOMEBREW_PREFIX="$(brew --prefix)"
    fi
fi

# ───────────────────────────────────────────────────────────────────────────────
# XDG Base Directory Compliance
# ───────────────────────────────────────────────────────────────────────────────
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# >>> maxfiles / nofile limit >>>
if [[ "$OSTYPE" == darwin* ]]; then
  ulimit -Sn 65536 2>/dev/null || true
fi
# <<< maxfiles / nofile limit <<<

# ───────────────────────────────────────────────────────────────────────────────
# Core Environment Variables
# ───────────────────────────────────────────────────────────────────────────────
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export EDITOR="/Applications/Cursor.app/Contents/Resources/app/bin/cursor -w"
export VISUAL="$EDITOR"
export PAGER="less"
export LESS="-R -F -X"

# Tool-specific homes
export PIPX_HOME="${XDG_DATA_HOME}/pipx"
export PIPX_BIN_DIR="$HOME/.local/bin"
export PNPM_HOME="$HOME/Library/pnpm"
export TESSDATA_PREFIX="/opt/homebrew/share/tessdata"

# .NET (use Homebrew prefix if available)
if [[ -n "$HOMEBREW_PREFIX" && -d "$HOMEBREW_PREFIX/opt/dotnet/libexec" ]]; then
    export DOTNET_ROOT="$HOMEBREW_PREFIX/opt/dotnet/libexec"
fi

# ───────────────────────────────────────────────────────────────────────────────
# CLI Power Tools Configuration
# ───────────────────────────────────────────────────────────────────────────────
# ripgrep (uses ~/.ripgreprc for defaults)
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# fzf
if command -v fzf &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow'
    export FZF_DEFAULT_OPTS='--height 50% --layout=reverse --border'
    export FZF_CTRL_T_OPTS="--preview 'bat -n --color=always {} 2>/dev/null || cat {}'"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow'
fi

# ───────────────────────────────────────────────────────────────────────────────
# Homebrew Compiler/Linker Flags (guarded)
# ───────────────────────────────────────────────────────────────────────────────
if [[ -n "$HOMEBREW_PREFIX" ]]; then
    # Build flags for common dependencies
    local -a cppflags_parts=() ldflags_parts=() pkg_parts=()

    # OpenJDK
    [[ -d "$HOMEBREW_PREFIX/opt/openjdk/include" ]] && cppflags_parts+=("-I$HOMEBREW_PREFIX/opt/openjdk/include")

    # curl
    [[ -d "$HOMEBREW_PREFIX/opt/curl/include" ]] && cppflags_parts+=("-I$HOMEBREW_PREFIX/opt/curl/include")
    [[ -d "$HOMEBREW_PREFIX/opt/curl/lib" ]]     && ldflags_parts+=("-L$HOMEBREW_PREFIX/opt/curl/lib")
    [[ -d "$HOMEBREW_PREFIX/opt/curl/lib/pkgconfig" ]] && pkg_parts+=("$HOMEBREW_PREFIX/opt/curl/lib/pkgconfig")

    # Qt5
    [[ -d "$HOMEBREW_PREFIX/opt/qt@5/include" ]] && cppflags_parts+=("-I$HOMEBREW_PREFIX/opt/qt@5/include")
    [[ -d "$HOMEBREW_PREFIX/opt/qt@5/lib" ]]     && ldflags_parts+=("-L$HOMEBREW_PREFIX/opt/qt@5/lib")
    [[ -d "$HOMEBREW_PREFIX/opt/qt@5/lib/pkgconfig" ]] && pkg_parts+=("$HOMEBREW_PREFIX/opt/qt@5/lib/pkgconfig")

    # Export only if we have values
    (( ${#cppflags_parts[@]} )) && export CPPFLAGS="${cppflags_parts[*]}"
    (( ${#ldflags_parts[@]} ))  && export LDFLAGS="${ldflags_parts[*]}"
    (( ${#pkg_parts[@]} ))      && export PKG_CONFIG_PATH="${(j.:.)pkg_parts}"

    # NOTE: DYLD_LIBRARY_PATH is stripped by macOS SIP for system binaries.
    # Only set if you have a specific need and understand the implications.
    # Commented out by default as it rarely works as expected:
    # export DYLD_LIBRARY_PATH="$HOMEBREW_PREFIX/opt/cairo/lib:${DYLD_LIBRARY_PATH}"
fi

# ───────────────────────────────────────────────────────────────────────────────
# PATH Assembly
# Order: user tools → language managers → Homebrew → system
# ───────────────────────────────────────────────────────────────────────────────
path=(
    # User-local binaries (highest priority)
    $HOME/.local/bin
    $PIPX_BIN_DIR
    $HOME/go/bin
    $PNPM_HOME

    # Language version managers
    $HOME/.rbenv/bin
    $HOME/.pyenv/bin

    # Antigravity (if installed)
    $HOME/.antigravity/antigravity/bin(N)

    # Homebrew core + keg-only overrides
    ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/opt/rustup/bin}
    ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/bin}
    ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/sbin}
    ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/opt/make/libexec/gnubin}
    ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/opt/coreutils/libexec/gnubin}
    ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/opt/findutils/libexec/gnubin}
    ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/opt/gnu-sed/libexec/gnubin}
    ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/opt/grep/libexec/gnubin}
    ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/opt/curl/bin}
    ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/opt/openjdk/bin}
    ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/opt/qt@5/bin}
    ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/opt/sphinx-doc/bin}

    # System paths (inherited)
    $path
)

# ───────────────────────────────────────────────────────────────────────────────
# Function Path (fpath) for completions & autoloaded functions
# ───────────────────────────────────────────────────────────────────────────────
fpath=(
    # Homebrew completions
    ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/share/zsh/site-functions}

    # User completions & functions
    $HOME/.zfunc(N)
    $HOME/.zsh/functions(N)

    # Docker CLI completions
    $HOME/.docker/completions(N)

    # System fpath (inherited)
    $fpath
)

# ───────────────────────────────────────────────────────────────────────────────
# Oh My Zsh Configuration
# ───────────────────────────────────────────────────────────────────────────────
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

# Update behavior
zstyle ':omz:update' mode reminder
zstyle ':omz:update' frequency 14

# Disable autocorrect (often more annoying than helpful)
ENABLE_CORRECTION="false"

# Tell OMZ vscode plugin to use Cursor
VSCODE=cursor

# Plugins
# NOTE: Order can matter. Heavy plugins should come later.
# Removed redundant plugins (rbenv handled by explicit init below)
plugins=(
    # Core utilities
    aliases
    command-not-found
    colored-man-pages
    colorize
    copyfile
    copypath
    encode64
    extract
    history
    jsontools
    per-directory-history
    safe-paste
    sudo
    zsh-interactive-cd

    # macOS specific
    macos

    # Development - Git
    git
    git-commit
    gitignore
    gh

    # Development - Containers
    docker
    docker-compose

    # Development - Cloud/Infra
    aws
    direnv
    terraform
	postgres

    # Development - Languages/Runtimes
    # NOTE: nvm plugin disabled in favor of lazy-loading below
    # nvm
    bun
    pip
    python
    pylint
    poetry
    poetry-env
    pyenv
    ruby
    uv

    # Development - Tools
    npm
    vscode
    stripe

    # Fun/Misc
    catimg
    emoji
    emoji-clock
    qrcode
    web-search

    # External (must be installed separately)
    zsh-wakatime
)

# Load Oh My Zsh
source "$ZSH/oh-my-zsh.sh"

# External interactive plugins loaded explicitly for deterministic ordering.
typeset -ga ZSH_AUTOSUGGEST_STRATEGY=(history completion)
typeset -g ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
[[ -f /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] \
  && source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# ───────────────────────────────────────────────────────────────────────────────
# fzf Keybindings & Completion (after OMZ, requires fpath set)
# ───────────────────────────────────────────────────────────────────────────────
if command -v fzf &>/dev/null && [[ -n "$HOMEBREW_PREFIX" ]]; then
    [[ -f "$HOMEBREW_PREFIX/opt/fzf/shell/key-bindings.zsh" ]] && source "$HOMEBREW_PREFIX/opt/fzf/shell/key-bindings.zsh"
    [[ -f "$HOMEBREW_PREFIX/opt/fzf/shell/completion.zsh" ]] && source "$HOMEBREW_PREFIX/opt/fzf/shell/completion.zsh"
fi

# Restore zsh-interactive-cd's Tab binding after fzf keybindings overwrite it.
if (( $+functions[zic-completion] )); then
    bindkey "${zic_custom_binding:-^I}" zic-completion
fi

# ───────────────────────────────────────────────────────────────────────────────
# Tool Initializations
# ───────────────────────────────────────────────────────────────────────────────

# rbenv (explicit init, more reliable than OMZ plugin)
if command -v rbenv &>/dev/null; then
    eval "$(rbenv init - zsh)"
fi

# pyenv (if not using OMZ pyenv plugin exclusively)
# Uncomment if you need pyenv virtualenv support:
# if command -v pyenv &>/dev/null; then
#     eval "$(pyenv init - zsh)"
#     eval "$(pyenv virtualenv-init - 2>/dev/null)"
# fi

# VS Code shell integration
if [[ "$TERM_PROGRAM" == "vscode" ]] && command -v cursor &>/dev/null; then
    source "$(cursor --locate-shell-integration-path zsh 2>/dev/null)" 2>/dev/null || true
fi

# Ghostty shell integration (custom bell sound + long-command notifications)
[[ "$TERM_PROGRAM" == "ghostty" ]] && source ~/.config/ghostty/shell-integration.zsh

# ───────────────────────────────────────────────────────────────────────────────
# Secrets & Local Overrides
# ───────────────────────────────────────────────────────────────────────────────
# Secrets file should contain: export VAR="value"
# File permissions should be 600: chmod 600 ~/.zsh/secrets.env
if [[ -f "$HOME/.zsh/secrets.env" ]]; then
    # Only source if permissions are 600 (silent — console output breaks p10k instant prompt)
    if [[ "$(/usr/bin/stat -f '%A' "$HOME/.zsh/secrets.env" 2>/dev/null)" == "600" ]]; then
        source "$HOME/.zsh/secrets.env"
    fi
fi

# Machine-specific overrides (not committed to dotfiles)
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
[[ -f "$HOME/.config/copilot-subagents.env" ]] && source "$HOME/.config/copilot-subagents.env"

# ───────────────────────────────────────────────────────────────────────────────
# Aliases
# ───────────────────────────────────────────────────────────────────────────────

# Shell management
alias c='clear'
alias zshconfig="\$EDITOR ~/.zshrc"
alias zshedit="\$EDITOR ~/.zshrc"
alias zshreload='exec zsh'
alias ohmyzsh="\$EDITOR ~/.oh-my-zsh"

# GNU coreutils compatibility (gtimeout from coreutils)
alias timeout='gtimeout'

# Safety nets
alias rm='rm -i'
alias mv='mv -i'
alias cp='cp -i'

# Modern CLI replacements
# eza (exa successor) - git-aware ls
if command -v eza &>/dev/null; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza -l --git --icons --group-directories-first'
    alias la='eza -la --git --icons --group-directories-first'
    alias lt='eza -T --icons --git-ignore -L 3'
    alias ltl='eza -T --icons --git-ignore -L 5'
fi

# bat - syntax-highlighted cat
command -v bat &>/dev/null && alias cat='bat --paging=never'

# fd - faster find (don't alias over find; scripts expect GNU find behavior)
command -v fd &>/dev/null && alias fdf='fd'

# NOTE: Don't alias grep→rg globally; breaks scripts expecting GNU grep.
# Use `rg` directly when you want ripgrep.

# dust/duf - modern du/df
command -v dust &>/dev/null && alias du='dust'
command -v duf  &>/dev/null && alias df='duf'

# lazygit - TUI for git
command -v lazygit &>/dev/null && alias lg='lazygit'

# MCP Hub (with explicit config)
alias mcphub='PORT=7654 MCPHUB_SETTING_PATH="$HOME/dev/tools/mcp/mcphub/mcp_settings.json" mcphub'
alias mcphubtunnel='cloudflared tunnel --config ~/.cloudflared/config.yml run mcphub'

# Quick navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# ───────────────────────────────────────────────────────────────────────────────
# Custom Functions (Autoloaded)
# ───────────────────────────────────────────────────────────────────────────────

# code → Cursor wrapper (calls binary directly to avoid recursion)
code() { /Applications/Cursor.app/Contents/Resources/app/bin/cursor "$@" }

# freshen — system maintenance: brew + caches + App Store
autoload -Uz freshen 2>/dev/null

# sync-cursor — merge VS Code Insiders profile into Cursor (settings + extensions)
autoload -Uz sync-cursor 2>/dev/null

# yazi — terminal file manager with CWD sync
function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    command yazi "$@" --cwd-file="$tmp"
    IFS= read -r -d '' cwd < "$tmp"
    [ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
    rm -f -- "$tmp"
}

# Add any other autoloaded functions here:
# autoload -Uz myfunc

# ───────────────────────────────────────────────────────────────────────────────
# Powerlevel10k Theme Configuration
# Run `p10k configure` to regenerate ~/.p10k.zsh
# ───────────────────────────────────────────────────────────────────────────────
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# GitHub Copilot CLI aliases (added by setup script)
if command -v gh &>/dev/null; then
    _gh_copilot_cache="${XDG_CACHE_HOME:-$HOME/.cache}/gh-copilot-aliases.zsh"
    if [[ ! -f "$_gh_copilot_cache" ]] || [[ "$_gh_copilot_cache" -ot "$(command -v gh)" ]]; then
        gh copilot alias -- zsh > "$_gh_copilot_cache" 2>/dev/null
    fi
    [[ -f "$_gh_copilot_cache" ]] && source "$_gh_copilot_cache"
    unset _gh_copilot_cache
fi

# Gemini CLI aliases
alias gm="gemini"
alias gm3="gemini -m gemini-3.0-pro-max"  # Max thinking + context
alias gmy="gemini -y"  # YOLO mode


# OpenCode CLI aliases
alias ocr="opencode run"
alias occ="opencode --continue"  # Continue last session


# Cursor CLI aliases
alias cur="cursor"
alias curp="cursor ."  # Open current directory in Cursor

# Playwright: skip bundled browser downloads, use system Chrome
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
alias chrome-debug='open -a "Google Chrome" --args --remote-debugging-port=9222'

# yt-dlp: maximum quality, fully enriched download
# NOTE: --sponsorblock-remove all takes precedence over --sponsorblock-mark all for
# overlapping categories. Remove --sponsorblock-mark if you want chapters preserved.
alias ytdown='yt-dlp \
  -f "bv*+ba/b" \
  -S "res,fps,hdr:12,vcodec,br,asr" \
  --merge-output-format mkv \
  --remote-components ejs:github \
  --embed-metadata \
  --embed-thumbnail \
  --embed-chapters \
  --add-metadata \
  --embed-subs \
  --sub-langs "all,-live_chat" \
  --sponsorblock-mark all \
  --sponsorblock-remove all \
  --download-archive "$HOME/Downloads/yt-archive.txt" \
  --concurrent-fragments 8 \
  --retries 10 \
  --extractor-retries 10 \
  --retry-sleep extractor:5 \
  --no-mtime \
  --no-part \
  -o "$HOME/Downloads/%(upload_date>%Y-%m-%d)s - %(uploader)s - %(title).200B [%(id)s].%(ext)s"'

# OF-Scraper aliases
alias ofs="ofscraper"
alias ofs-all="ofscraper --posts all --username ALL --action download"
alias ofs-daemon="ofscraper --daemon 10 --posts all --action download"
alias ofs-debug="ofscraper --output debug"
# Docker CLI completions already configured in fpath block above (line ~165).

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/ww/.cache/lm-studio/bin"
# End of LM Studio CLI section

# Draw Things CLI wrapper
export PATH="$HOME/.config/draw-thing:$PATH"
export DRAWTHINGS_OUTPUT_DIR="$HOME/Pictures/draw-thing"

# opencode
export PATH=/Users/ww/.opencode/bin:$PATH
if [[ ":$PATH:" != *":/Users/ww/dev/projects/agents/bin:"* ]]; then
  export PATH="/Users/ww/dev/projects/agents/bin:$PATH"
fi
# Added by dbt Fusion extension (ensure dbt binary dir on PATH)
if [[ ":$PATH:" != *":/Users/ww/.local/bin:"* ]]; then
  export PATH=/Users/ww/.local/bin:"$PATH"
fi
# Added by dbt Fusion extension
alias dbtf=/Users/ww/.local/bin/dbt

# zsh-syntax-highlighting must be loaded at the end of interactive setup.
[[ -f /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] \
  && source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# ═══════════════════════════════════════════════════════════════════════════════
# End of user configuration
# ═══════════════════════════════════════════════════════════════════════════════

if [[ ":$PATH:" != *":$HOME/dev/tools/bin:"* ]]; then
  export PATH="$HOME/dev/tools/bin:$PATH"
fi

# Amazon Q post block. Keep at the bottom of this file.
[[ -f "${HOME}/Library/Application Support/amazon-q/shell/zshrc.post.zsh" ]] && builtin source "${HOME}/Library/Application Support/amazon-q/shell/zshrc.post.zsh"
export OPENCODE_ALLOW_SECRET_FILES=1
export PATH="/Users/ww/.cache/.bun/bin:$PATH"
# The following lines have been added by Docker Desktop to enable Docker CLI completions.
fpath=(/Users/ww/.docker/completions $fpath)
autoload -Uz compinit
compinit
# End of Docker CLI completions
eval "$(direnv hook zsh)"
eval "$(mise activate zsh)"
eval "$(mise hook-env -s zsh)"



export PATH=$PATH:/Users/ww/.spicetify




# >>> grok installer >>>
export PATH="$HOME/.grok/bin:$PATH"
fpath=(~/.grok/completions/zsh $fpath)
autoload -Uz compinit && compinit -C
# <<< grok installer <<<

# pnpm
export PNPM_HOME="/Users/ww/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
# pnpm end
