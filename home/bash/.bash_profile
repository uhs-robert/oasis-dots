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

# This repeats the block at the end of .bashrc. cargo and rbenv above prepend to PATH after .bashrc has run, so the
# shims need moving to the front again here.
# Agent shims (the optional agents package) go first on PATH, after every other change to it, so `claude` and the
# other agents run capped in agents.slice. An entry inherited from Hyprland is moved to the front, not doubled.
_agent_shims="$HOME/.local/share/agent-shims/bin"
if [[ -d $_agent_shims ]]; then
  _path=":$PATH:"
  _path="${_path//:$_agent_shims:/:}"
  _path="${_path#:}"
  _path="${_path%:}"
  PATH="$_agent_shims${_path:+:$_path}"
  export PATH
  unset _path
fi
unset _agent_shims
