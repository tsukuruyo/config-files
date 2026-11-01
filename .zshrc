# 再読み込み (. ~/.zshrc) で PATH が重複して伸びないようにする
typeset -U path PATH

# --------------------------------------------------------------------------------
# Homebrew
# --------------------------------------------------------------------------------
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
# brew upgrade は自分で実行する。brew install のついでに更新させない
export HOMEBREW_NO_INSTALL_UPGRADE=1

# --------------------------------------------------------------------------------
# sheldon
# --------------------------------------------------------------------------------
if (( $+commands[sheldon] )); then
  eval "$(sheldon source)"
fi

# --------------------------------------------------------------------------------
# Terminal
# --------------------------------------------------------------------------------
export LANG=ja_JP.UTF-8
export EDITOR=vim
export VISUAL=vim
export PAGER=less
export LESSHISTFILE=-
setopt no_beep
unsetopt BEEP

# colors
export LSCOLORS=gxfxcxdxbxegedabagacad
export LS_COLORS="di=01;36:ln=01;35:so=32:pi=33:ex=01;32:bd=46;34:cd=43;34:su=41;30:sg=46;30:tw=42;30:ow=01;30;46"
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
autoload -Uz colors
colors

# aliases
alias claude='\claude agents --cwd .'
alias c='claude'
alias cx='\codex'
alias d='\docker'
alias g='\git'
alias kc='\kubectl'
alias ls='\ls -GF --color'
alias pn='\pnpm'

# emacs like binding
bindkey -e

# history
HISTFILE=${HOME}/.zsh_history
HISTSIZE=1000000
SAVEHIST=1000000
# トークンやパスワードを含みそうなコマンドは履歴ファイルに書かない
# （ほかのコマンドも、先頭にスペースを付ければ hist_ignore_space で記録されない）
HISTORY_IGNORE='(*(TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|token|secret|password|passwd|api_key)*)'
setopt share_history
setopt hist_ignore_dups
#setopt hist_ignore_all_dups
setopt hist_find_no_dups
setopt hist_ignore_space
setopt hist_reduce_blanks
setopt extended_history
setopt print_eight_bit
setopt auto_cd
setopt auto_pushd
setopt pushd_ignore_dups

if [[ -n $(echo ${^fpath}/chpwd_recent_dirs(N)) && -n $(echo ${^fpath}/cdr(N)) ]]; then
  # cdr は履歴ファイルのディレクトリを作らないので、新しい Mac では先に作る
  mkdir -p "${HOME}/.cache"
  autoload -Uz chpwd_recent_dirs cdr add-zsh-hook
  add-zsh-hook chpwd chpwd_recent_dirs
  zstyle ':completion:*' recent-dirs-insert both
  zstyle ':chpwd:*' recent-dirs-default true
  zstyle ':chpwd:*' recent-dirs-max 1000
  zstyle ':chpwd:*' recent-dirs-file "$HOME/.cache/chpwd-recent-dirs"
fi

# 単語の区切り文字
autoload -Uz select-word-style
select-word-style default
zstyle ':zle:*' word-chars " /=;@:{},|"
zstyle ':zle:*' word-style unspecified

# completion
autoload -Uz compinit
# キャッシュ（~/.zcompdump）は1日1回だけ作り直し、そのときは compaudit で
# 補完関数のディレクトリが他人に書き換えられないかも確かめる。それ以外は速さを優先する
() {
  local dump=${ZDOTDIR:-$HOME}/.zcompdump
  local -a stale=($dump(N.mh+24))
  if [[ ! -f $dump ]] || (( $#stale )); then
    compinit -d $dump
  else
    compinit -C -d $dump
  fi
}
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}'
zstyle ':completion:*' menu select
zstyle ':completion:*' completer _expand _complete _approximate

# path
# 自分で書き込めるディレクトリは末尾に置き、同じ名前のシステムや brew のコマンドを上書きさせない
export PATH="${PATH}:${HOME}/bin:${HOME}/.local/bin"

# --------------------------------------------------------------------------------
# Starship
# --------------------------------------------------------------------------------
if (( $+commands[starship] )); then
  eval "$(starship init zsh)"
fi

# --------------------------------------------------------------------------------
# fzf
# --------------------------------------------------------------------------------
if (( $+commands[fzf] )); then
  # search shell history (ctrl + r)
  function fzf-select-history() {
    BUFFER=$(history -n -r 1 | awk '!seen[$0]++' | fzf --query "$LBUFFER" --height 40% --tac)
    CURSOR=$#BUFFER
    zle reset-prompt
  }
  zle -N fzf-select-history
  bindkey '^r' fzf-select-history

  # cdr (ctrl + t)
  function fzf-cdr () {
    local selected_dir=$(cdr -l | awk '{ print $2 }' | fzf --query "$LBUFFER" --reverse --height 40% \
      --preview 'f() { sh -c "ls -CF $1" }; f {}')
    if [ -n "$selected_dir" ]; then
      BUFFER="cd ${selected_dir}"
      zle accept-line
    fi
    zle reset-prompt
  }
  zle -N fzf-cdr
  bindkey '^t' fzf-cdr

  # ghq (ctrl + ])
  function fzf-src () {
    local selected_dir=$(ghq list -p | fzf --query "$LBUFFER" --reverse --height 40% \
      --preview 'ls -CF {} | head -20')
    if [ -n "$selected_dir" ]; then
      BUFFER="cd ${selected_dir}"
      zle accept-line
    fi
    zle reset-prompt
  }
  zle -N fzf-src
  bindkey '^]' fzf-src

  # git switch branch
  fbr() {
    git branch | sed 's/^[ *]*//' | fzf --query "$LBUFFER" --reverse --height 40% \
      --preview 'git log --oneline --graph --color=always {} | head -20' \
      --bind='enter:become(git switch {})'
  }
fi

# --------------------------------------------------------------------------------
# Google cloud SDK
# --------------------------------------------------------------------------------
# The next line updates PATH for the Google Cloud SDK.
if [ -f "${HOME}/google-cloud-sdk/path.zsh.inc" ]; then
  . "${HOME}/google-cloud-sdk/path.zsh.inc"
fi

# The next line enables shell command completion for gcloud.
if [ -f "${HOME}/google-cloud-sdk/completion.zsh.inc" ]; then
  . "${HOME}/google-cloud-sdk/completion.zsh.inc"
fi

export USE_GKE_GCLOUD_AUTH_PLUGIN=True

# --------------------------------------------------------------------------------
# .NET
# --------------------------------------------------------------------------------
export DOTNET_CLI_TELEMETRY_OPTOUT=1

# --------------------------------------------------------------------------------
# LM Studio CLI (lms)
# --------------------------------------------------------------------------------
if [[ -d "${HOME}/.lmstudio/bin" ]]; then
  export PATH="$PATH:${HOME}/.lmstudio/bin"
fi

# --------------------------------------------------------------------------------
# Unity CLI
# --------------------------------------------------------------------------------
if [[ -f "${HOME}/.unity/env" ]]; then
  . "${HOME}/.unity/env"
fi

# --------------------------------------------------------------------------------
# mise
# --------------------------------------------------------------------------------
if [[ -x "${HOME}/.local/bin/mise" ]]; then
  eval "$("${HOME}/.local/bin/mise" activate zsh)"
fi
