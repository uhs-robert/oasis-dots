# Non-interactive shells (commands over ssh) never read .zshrc, so the PATH entry lives here too.
(( ${path[(Ie)$HOME/.local/bin]} )) || path+=("$HOME/.local/bin")
