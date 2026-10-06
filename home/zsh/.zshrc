# Add deno completions to search path
if [[ ":$FPATH:" != *":$HOME/.zsh/completions:"* ]]; then export FPATH="$HOME/.zsh/completions:$FPATH"; fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# History
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt EXTENDED_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY
setopt SHARE_HISTORY
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY

setopt AUTO_CD
setopt CORRECT
setopt PROMPT_SUBST
setopt INTERACTIVE_COMMENTS
# Coding agents pass globs like grep --include=*.lua unquoted; let an unmatched glob through as text, the way bash does.
[[ -n $CLAUDECODE ]] && setopt NO_NOMATCH

ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# Fastfetch
ff() {
  fastfetch
}

# Show fastfetch immediately on startup if not a floating terminal
if [[ -o interactive && -n "$HYPRLAND_INSTANCE_SIGNATURE" && -z "$NO_FASTFETCH" ]]; then
  is_floating=$(hyprctl activewindow -j 2>/dev/null | jq -r '.floating // empty')

  if [[ "$is_floating" != "true" ]]; then
    fastfetch
  fi
fi

# zsh-vi-mode: keep normal blinking terminal cursor
function zvm_config() {
  ZVM_NORMAL_MODE_CURSOR=$ZVM_CURSOR_BLINKING_BLOCK
  ZVM_INSERT_MODE_CURSOR=$ZVM_CURSOR_BLINKING_BEAM
  ZVM_OPPEND_MODE_CURSOR=$ZVM_CURSOR_BLINKING_BLOCK
}

# Completion
autoload -Uz compinit
compinit

# Antidote plugin manager
source "/usr/share/zsh-antidote/antidote.zsh"
antidote load "$HOME/.zsh_plugins.txt"

bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

eval "$(starship init zsh)"

# User configuration

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='nvim' # swap to vim if needed
else
  export EDITOR='nvim'
fi

# SSH: use common remote terminfo instead of foot
ssh() {
  case "$TERM" in
    kitty)
      command ssh "$@"
      ;;
    *)
      TERM=xterm-256color command ssh "$@"
      ;;
  esac
}

# SSH fuzzy host picker
ssh_hosts() {
  [[ -r "$HOME/.ssh/config" ]] || return 0
  awk '
    { sub(/#.*/, ""); sub(/^[ \t]*/, ""); sub(/^[Hh][Oo][Ss][Tt][ \t]*=[ \t]*/, "Host ") }
    tolower($1) == "host" {
      for (i = 2; i <= NF; i++) {
        host = $i
        gsub(/^[\047"]|[\047"]$/, "", host)
        if (host != "" && host !~ /[!*?\[]/ && host !~ /^-/) print host
      }
    }
  ' "$HOME/.ssh/config" | sort -u
}

s() {
  local host
  host=$(ssh_hosts | fzf --prompt='SSH > ' --height=60% --layout=reverse) || return
  [[ -n "$host" ]] && ssh "$host" "$@"
}

export VISUAL="$EDITOR"
export GIT_EDITOR="$EDITOR"
export SUDO_EDITOR="env SUDOEDIT=1 $EDITOR"
export MANPAGER='nvim +Man!'
export PAGER="less -RF --mouse"

# For nmtui
export NEWT_COLORS='root=,black window=white,black border=brown,black title=red,black textbox=white,black label=white,black entry=red,black disentry=gray,black button=black,cyan actbutton=black,cyan compactbutton=green,black listbox=white,black actlistbox=red,black sellistbox=white,green actsellistbox=black,cyan checkbox=white,black actcheckbox=black,cyan emptyscale=gray,black fullscale=black,green helpline=green,black roottext=green,black'

# Auto completion
unsetopt BEEP

# Install fzf if available
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
export FZF_DEFAULT_OPTS="--height=80% --layout=reverse --border --preview 'bat --style=numbers --color=always {} || sed -n \"1,200p\" -- {}' --preview-window=right:60%:border-left --bind=ctrl-p:toggle-preview"
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
f(){ "${EDITOR:-nvim}" -- "$(fzf)"; }

# Disable auto-pagination (prevents big dumps)
zstyle ':completion:*' list-colors ''

# Add user script directories to PATH
export PATH="$PATH:$HOME/.local/share/dotfiles/repos/rob-bin/bin/"
export PATH="$HOME/.config/hypr/scripts:$PATH"
export PATH="$HOME/.tmuxifier/bin:$PATH"

# Add language directories to PATH
export PATH="$(npm root -g)/.bin:$PATH"
export PATH="$HOME/.npm-global/bin:$PATH"
export PATH="$HOME/.local/share/npm/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"
# Ruby user gem executables. Globs every installed version and skips silently
# when Ruby is absent, so this file stays portable across machines.
for _gem_bin in "$HOME"/.local/share/gem/ruby/*/bin(N/) "$HOME"/.gem/ruby/*/bin(N/); do
  export PATH="$_gem_bin:$PATH"
done
unset _gem_bin
# export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export PATH="$PATH:$HOME/.lmstudio/bin"

# Load aliases & functions from GitHub-controlled script
if [[ -f "$HOME/.local/share/dotfiles/repos/rob-bin/lib/functions.sh" ]]; then
  source "$HOME/.local/share/dotfiles/repos/rob-bin/lib/functions.sh"
fi
alias src='source ~/.zshrc'

# Load user-specific scripts from ~/.bashrc.d
for rc in ~/.bashrc.d/*(.N); do source "$rc"; done

command -v tmuxifier >/dev/null && eval "$(tmuxifier init -)"

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# yazi
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	YAZI_CWD_FILE="$tmp" command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}
# yazi end

# Zoxide
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
# Zoxide end

# Lsd
alias ls='lsd'
alias l='ls -l'
alias la='ls -a'
alias lla='ls -la'
alias lt='ls --tree'
# Lsd end


# tdf, oasis moonlight dark
alias tdf='tdf -w 1E2A38 -b F5F5DC'

# Just
alias j='just'

jg() {
  just --justfile "$HOME/.config/just/justfile" \
       --working-directory "$HOME" \
       "$@"
}

_jg() {
  local -a recipes
  recipes=(${=$(jg --summary 2>/dev/null)})
  compadd -- "${recipes[@]}"
}

compdef _jg jg
# Just End

# IntelliShell
export INTELLI_HOME="$HOME/.local/share/intelli-shell"
export INTELLI_SEARCH_HOTKEY='^G'
# export INTELLI_VARIABLE_HOTKEY='^l'
# export INTELLI_BOOKMARK_HOTKEY='^b'
# export INTELLI_FIX_HOTKEY='^x'
# export INTELLI_SKIP_ESC_BIND=0
# alias is="intelli-shell"
export PATH="$INTELLI_HOME/bin:$PATH"
[[ -f ~/.config/secrets/intellishell.env ]] && source ~/.config/secrets/intellishell.env
command -v intelli-shell >/dev/null && eval "$(intelli-shell init zsh)"

# Machine-local additions kept outside this repo
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
