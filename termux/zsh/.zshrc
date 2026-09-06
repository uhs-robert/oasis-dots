[[ -o interactive ]] || return

export EDITOR=nvim VISUAL=nvim
# Resolve the checkout from this Stow link, even when cloned outside ~/dotfiles.
export TERMUX_DOTFILES=${${(%):-%x}:A:h:h:h}
export PATH="$HOME/.local/bin:$PATH"
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt APPEND_HISTORY SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_SAVE_NO_DUPS HIST_REDUCE_BLANKS
bindkey -v
KEYTIMEOUT=10
bindkey '^R' history-incremental-search-backward
bindkey '^?' backward-delete-char

source "$HOME/.config/zsh/ssh-hosts.zsh"
autoload -Uz compinit
compinit
zstyle ':completion:*' menu no
# Both entry points use the same literal Host aliases. No known_hosts registry.
_ssh_hosts() {
    local -a hosts expl
    hosts=("${(@f)$(termux_ssh_hosts)}")
    _wanted hosts expl 'SSH host' compadd "$@" -a hosts
}
source "$HOME/.local/share/zsh/plugins/fzf-tab/fzf-tab.plugin.zsh"
if [[ -r "$PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
    source "$PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
else
    source "$HOME/.local/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

s() {
    local host
    host=$(termux_ssh_hosts | fzf --prompt='SSH > ' --height=60% --layout=reverse) || return
    [[ -n "$host" ]] && command ssh -- "$host" "$@"
}
y() {
    local tmp cwd
    tmp=$(mktemp) || return
    command yazi "$@" --cwd-file="$tmp"
    if [[ -s "$tmp" ]]; then
        cwd=$(<"$tmp")
        [[ -d "$cwd" && "$cwd" != "$PWD" ]] && builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}
alias v=nvim lg=lazygit up=topgrade
PROMPT='%F{blue}%1~%f %(?.%F{green}.%F{red})%#%f '

alias ls='lsd'
alias l='lsd -l'
alias ll='lsd -lh'
alias la='lsd -a'
alias lla='lsd -la'
alias lt='lsd --tree'

command -v fastfetch >/dev/null && fastfetch
