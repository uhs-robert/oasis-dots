# tmux/tmuxifier-layouts/ai.session.sh
# Set a custom session root path. Default is `$HOME`.
# Must be called before `initialize_session`.
session_root "$HOME/Development/"

# Check if tmux is running, and start it if not
if ! pgrep tmux >/dev/null; then
  tmux start-server
fi

session_name="AI"

# Create session with specified name if it does not already exist. If no
# argument is given, session name will be based on layout file name.
if initialize_session "$session_name"; then
  # Make the outer terminal/window title predictable.
  tmux set-option -t "$session_name" set-titles on
  tmux set-option -t "$session_name" set-titles-string "Tmux $session_name"

  new_window "Claude"
  run_cmd "cd $session_root"
  run_cmd "claude"

  new_window "Codex"
  run_cmd "cd $session_root"
  run_cmd "codex"

  select_window 1
fi

# Finalize session creation and switch/attach to it.
finalize_and_go_to_session
