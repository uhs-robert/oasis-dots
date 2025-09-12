# Add deno completions to search path
if [[ ":$FPATH:" != *":/home/USER/.zsh/completions:"* ]]; then export FPATH="/home/USER/.zsh/completions:$FPATH"; fi
# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
# ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
plugins=(
  colored-man-pages
  colorize
  dnf
  extract
  fzf
  git
  history-substring-search
  node
  npm
  nvm
  starship
  sudo
  vi-mode
  z
  zsh-autocomplete
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-vi-mode
)

source $ZSH/oh-my-zsh.sh

# User configuration

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='nvim' #swap to vim if needed
else
  export EDITOR='nvim'
fi

# Auto completion
unsetopt BEEP

# Install fzf if available
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Disable auto-pagination (prevents big dumps)
zstyle ':completion:*' list-colors ''

# Add custom script directory to PATH
export PATH="$PATH:/home/USER/Documents/github-uphill/bash-scripts/scripts/"
export PATH="$HOME/.config/hypr/scripts:$PATH"
export PATH="$HOME/.tmuxifier/bin:$PATH"
export PATH="$(npm root -g)/.bin:$PATH"
export PATH="$HOME/.npm-global/bin:$PATH"

# Load aliases & functions from GitHub-controlled script
if [[ -f "$HOME/Documents/github-uphill/bash-scripts/scripts/functions.sh" ]]; then
  source "$HOME/Documents/github-uphill/bash-scripts/scripts/functions.sh"
fi

# Load user-specific scripts from ~/.bashrc.d
for rc in ~/.bashrc.d/*(.N); do source "$rc"; done

eval "$(tmuxifier init -)"

# Check if running inside Hyprland and if the terminal is floating
if [[ -o interactive ]]; then
  is_floating=$(hyprctl activewindow -j | jq -r '.floating')
  if [[ "$is_floating" == "false" || -z "$is_floating" ]]; then
    fastfetch
  fi
fi
. "/home/USER/.deno/env"

# pnpm
export PNPM_HOME="/home/USER/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# yazi
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		builtin cd -- "$cwd"
	fi
	rm -f -- "$tmp"
}
# yazi end

# Zoxide
eval "$(zoxide init zsh)"
# Zoxide end

# Lsd
alias ls='lsd'
alias l='ls -l'
alias la='ls -a'
alias lla='ls -la'
alias lt='ls --tree'
# Lsd end

# Taskwarrior
alias t="task"
# Taskwarrior end

export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# Added by LM Studio CLI (lms)
export PATH="$PATH:/home/USER/.lmstudio/bin"
# End of LM Studio CLI section

export PATH=$PATH:$HOME/.local/bin
