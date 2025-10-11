# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
  . ~/.bashrc
fi

# User specific environment and startup programs
. "/home/USER/.deno/env"
# Added by LM Studio CLI (lms)
export PATH="$PATH:/home/USER/.lmstudio/bin"
# End of LM Studio CLI section
. "$HOME/.cargo/env"
