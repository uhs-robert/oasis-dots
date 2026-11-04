# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
  PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# Add custom script directory to PATH
export PATH="$PATH:$HOME/.local/share/dotfiles/repos/rob-bin/bin/"

# Load aliases & functions from GitHub-controlled script
if [ -f "$HOME/.local/share/dotfiles/repos/rob-bin/lib/functions.sh" ]; then
  source "$HOME/.local/share/dotfiles/repos/rob-bin/lib/functions.sh"
fi

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
  for rc in ~/.bashrc.d/*; do
    if [ -f "$rc" ]; then
      . "$rc"
    fi
  done
fi

unset rc
eval "$(starship init bash)"
if [[ $- == *i* ]]; then
  fastfetch
fi

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
