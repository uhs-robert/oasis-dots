# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
  . ~/.bashrc
fi

# User specific environment and startup programs
. "$HOME/.deno/env"
# Added by LM Studio CLI (lms)
export PATH="$PATH:$HOME/.lmstudio/bin"
# End of LM Studio CLI section
. "$HOME/.cargo/env"
eval "$(~/.rbenv/bin/rbenv init -)"
