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
