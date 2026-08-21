# ~/.zsh/aliases.zsh — curated interactive aliases (sourced from ~/.zshrc)
# Do not alias `oc`: agents/bin/oc is a real CLI (top history token on this rig).
# Descriptions: a `#:` line immediately above each `alias name=` (parsed by alias-help / als).

#: clear the terminal
alias c='clear'
#: edit ~/.zshrc in $EDITOR
alias zshconfig="\$EDITOR ~/.zshrc"
#: edit this alias catalog in $EDITOR
alias zshaliases="\$EDITOR ~/.zsh/aliases.zsh"
#: replace the current zsh process
alias zshreload='exec zsh'
#: edit Oh My Zsh in $EDITOR
alias ohmyzsh="\$EDITOR ~/.oh-my-zsh"
#: GNU timeout via gtimeout
alias timeout='gtimeout'
#: rm with confirmation
alias rm='rm -i'
#: mv with confirmation
alias mv='mv -i'
#: cp with confirmation
alias cp='cp -i'
#: cd to parent
alias ..='cd ..'
#: cd up two directories
alias ...='cd ../..'
#: cd up three directories
alias ....='cd ../../..'

# uv: avoid glob expansion on CLI args
#: uv without glob expansion
alias uv='noglob uv'

if command -v eza &>/dev/null; then
  #: eza listing (icons, dirs first)
  alias ls='eza --icons --group-directories-first'
  #: eza long listing with git
  alias ll='eza -l --git --icons --group-directories-first'
  #: eza long listing including hidden
  alias la='eza -la --git --icons --group-directories-first'
  #: eza tree, depth 3
  alias lt='eza -T --icons --git-ignore -L 3'
  #: eza tree, depth 5
  alias ltl='eza -T --icons --git-ignore -L 5'
fi
#: bat without paging
command -v bat &>/dev/null && alias cat='bat --paging=never'
#: dust disk usage
command -v dust &>/dev/null && alias du='dust'
#: duf disk free
command -v duf &>/dev/null && alias df='duf'
#: lazygit
command -v lazygit &>/dev/null && alias lg='lazygit'

#: mcphub on port 7654 with local settings
alias mcphub='PORT=7654 MCPHUB_SETTING_PATH="$HOME/dev/tools/mcp/mcphub/mcp_settings.json" mcphub'
#: cloudflared tunnel for mcphub
alias mcphubtunnel='cloudflared tunnel --config ~/.cloudflared/config.yml run mcphub'

#: OpenCode run
alias ocr="opencode run"
#: OpenCode continue
alias occ="opencode --continue"
#: OpenCode CLI (do not alias oc — that binary is agents/bin/oc)
alias opc='opencode'
#: OpenCode desktop app
alias opa='open -a OpenCode'
#: Codex CLI
alias cdx='codex'
#: Codex desktop app
alias cda='open -a ChatGPT'
#: Grok Build CLI
alias grk='grok'
#: Cursor IDE
alias cur="cursor"
#: Cursor IDE in the current directory
alias curp="cursor ."
#: Cursor CLI
alias agt='agent'
#: Chrome with remote debugging on 9222
alias chrome-debug='open -a "Google Chrome" --args --remote-debugging-port=9222'
#: local dbt wrapper
alias dbtf="$HOME/.local/bin/dbt"

#: yt-dlp download with archive and embeds
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

#: ofscraper
alias ofs="ofscraper"
#: ofscraper all posts for all usernames
alias ofs-all="ofscraper --posts all --username ALL --action download"
#: ofscraper daemon every 10s
alias ofs-daemon="ofscraper --daemon 10 --posts all --action download"
#: ofscraper debug output
alias ofs-debug="ofscraper --output debug"

#: brew install
alias bi='brew install'
#: brew upgrade (skipped if a bup binary exists)
(( $+commands[bup] )) || alias bup='brew upgrade'
#: freshen (autoload function)
alias fr='freshen'
#: freshen dry-run, plain, no color (safe first run)
alias frn='freshen --dry-run --progress=plain --no-color'
#: freshen clean-only, plain, no color
alias frc='freshen --clean-only --progress=plain --no-color'
#: freshen storage-plan (pass --restore-target-gib yourself)
alias frs='freshen --storage-plan'
#: ghostty validate-config
alias gtyv='ghostty +validate-config'
#: ghostty show-config, changes only
alias gtyc='ghostty +show-config --changes-only'
#: hyperfine benchmark with 3 warmups
command -v hyperfine &>/dev/null && alias bench='hyperfine --warmup 3'
#: jc pretty-print JSON
command -v jc &>/dev/null && alias jcp='jc -p'
#: mtr report mode, 20 cycles (macOS: sudo mtrc)
command -v mtr &>/dev/null && alias mtrc='mtr --report --report-cycles 20'
#: Atuin history recorded by AI coding agents
alias atuin-agents="atuin search --author '\$all-agent' -- ''"
if command -v xh &>/dev/null; then
  #: xh as httpie-compatible client
  (( $+commands[http] )) || alias http='xh'
  #: xh forcing HTTPS
  (( $+commands[https] )) || alias https='xh --https'
fi

# Catalog lister (do not name this function aliases — that is zsh's $aliases map)
alias-help() {
  emulate -L zsh
  setopt local_options extended_glob
  local file="${HOME}/.zsh/aliases.zsh"
  if [[ ! -r $file ]]; then
    print -u2 "alias-help: missing $file"
    return 1
  fi
  local prefix="${1:-}"
  local desc="" line name exp cont
  local -a out
  out+=("NAME	DESCRIPTION	EXPANSION")
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line##[[:space:]]##}
    if [[ $line == '#:'* ]]; then
      desc=${line#\#:}
      desc=${desc##[[:space:]]##}
      continue
    fi
    if [[ $line == '#'* ]]; then
      continue
    fi
    if [[ $line != '#'* && $line =~ 'alias[[:space:]]+([A-Za-z0-9_.+-]+)=' ]]; then
      name=${match[1]}
      exp=${line#*=}
      while [[ $exp == *\\ ]]; do
        exp=${exp%\\}
        exp=${exp%%[[:space:]]##}
        IFS= read -r cont || break
        exp+=" ${cont##[[:space:]]##}"
      done
      if [[ -z $prefix || $name == ${prefix}* ]]; then
        out+=("${name}	${desc}	${exp}")
      fi
    fi
    desc=""
  done <"$file"
  if command -v column >/dev/null 2>&1; then
    print -rl -- "${out[@]}" | column -s $'\t' -t
  else
    print -rl -- "${out[@]}"
  fi
}

#: list tracked aliases with descriptions
alias als='alias-help'
