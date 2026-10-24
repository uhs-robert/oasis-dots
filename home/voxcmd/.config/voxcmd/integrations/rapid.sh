# shellcheck shell=bash
# Hook library of rapid.toml: sourced before every hook and action of the integration.

rapid_leave_hint_text="say cortana done to leave"

rapid_leave_hint() {
  "$VOXCMD_SELF" util notify info "voxcmd: Rapid mode" "$rapid_leave_hint_text"
}

# Inside the session the mode-naming exit forms are a missed turn, not an exit: only "cortana ..." leaves. The verbs stay
# so that outside a session they still run before Media's and System's. A bare done or exit word becomes the hint's own
# phrase, so it routes to rapid_leave_hint per step; an empty rewrite would be the generic "Not understood" for the turn.
# Repeats count too: voxtype hears one "stop" as "Stop. Stop. Stop.", which the routing correction retry would shrink to
# a "stop" that pauses the music.
# The exit regex is the one `{mode_exit}` expands to, spelled out here: a rewrite hook cannot use pattern placeholders.
rapid_rewrite() {
  local exit_filler='(okay|ok|alright|please|now)'
  local exit_object='(the )?(rapid|rapid mode|rapid fire mode)'
  local exit_phrase="($exit_filler )*((stop|exit|quit|end|leave|finish|close|turn off|switch off) $exit_object|$exit_object off)( $exit_filler)*"
  local leave_words='done|im done|thats all|exit|quit|stop|done with (the )?(rapid|rapid mode|rapid fire mode)'
  if [[ "$1" =~ ^($exit_phrase)$ ]]; then return 0; fi
  if [[ "$1" =~ ^($leave_words)( ($leave_words))*$ ]]; then printf '%s' "$rapid_leave_hint_text"; return 0; fi
  printf '%s' "$1"
}
