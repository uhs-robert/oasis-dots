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


# IntelliShell
export INTELLI_HOME="/home/USER/.local/share/intelli-shell"
# export INTELLI_SEARCH_HOTKEY=\\C-@
# export INTELLI_VARIABLE_HOTKEY=\\C-l
# export INTELLI_BOOKMARK_HOTKEY=\\C-b
# export INTELLI_FIX_HOTKEY=\\C-x
# export INTELLI_SKIP_ESC_BIND=0
# alias is="intelli-shell"
export PATH="$INTELLI_HOME/bin:$PATH"
eval "$(intelli-shell init bash)"
