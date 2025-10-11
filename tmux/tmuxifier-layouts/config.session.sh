# layouts/config.session.sh
# Set a custom session root path. Default is `$HOME`.
# Must be called before `initialize_session`.
session_root "$HOME/dotfiles/"

# Check if tmux is running, and start it if not
if ! pgrep tmux >/dev/null; then
  tmux start-server
fi

# Create session with specified name if it does not already exist. If no
# argument is given, session name will be based on layout file name.
if initialize_session "CONFIG"; then
  new_window ""
  run_cmd "cd $session_root"
  run_cmd "yazi"
  new_window ""
  run_cmd "cd $session_root"
  select_window 1
fi

# Finalize session creation and switch/attach to it.
finalize_and_go_to_session
