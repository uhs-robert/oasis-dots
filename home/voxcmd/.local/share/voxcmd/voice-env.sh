# shellcheck shell=bash
# Voice settings saved by Quickshell's Settings > Voice, read by voxcmd and voxtype-daemon.
#
# The file sits outside the stow-folded ~/.config/voxcmd, which links into the public repo. It is read as data, never sourced:
# only lines of the shape KEY=NUMBER with a VOXCMD_ key count (VOXCMD_WAKE_SENSITIVITY takes one of its level names
# instead), so a stray line cannot run anything.

voice_env_file() {
  printf '%s\n' "${VOXCMD_VOICE_ENV_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/voxcmd/voice.env}"
}

# voice_env_value KEY: prints the environment's value, else the file's last valid line for KEY. Fails, printing nothing,
# when neither has one, so the caller's default applies.
voice_env_value() {
  local key="$1" line file value_pattern='[0-9]+(\.[0-9]+)?'
  [ "$key" != VOXCMD_WAKE_SENSITIVITY ] || value_pattern='[a-z]+'
  if [ -n "${!key:-}" ]; then
    printf '%s\n' "${!key}"
    return 0
  fi
  file="$(voice_env_file)"
  [ -r "$file" ] || return 1
  line="$(grep -E "^${key}=${value_pattern}\$" "$file" 2>/dev/null | tail -n 1)" || return 1
  [ -n "$line" ] || return 1
  voice_env_acceptable "$key" "${line#*=}" || return 1
  printf '%s\n' "${line#*=}"
}

# The same limits Settings > Voice enforces, so a hand-edited value out of range falls back to the default.
# Environment values are not checked here: as before, they are the user's explicit choice.
voice_env_acceptable() {
  local key="$1" value="$2"
  case "$key" in
    VOXCMD_DUCK_MEDIA_VOLUME) [[ "$value" =~ ^[0-9]+$ ]] && ((10#$value <= 100)) ;;
    VOXCMD_WAKE_SENSITIVITY) [[ "$value" == strict || "$value" == balanced || "$value" == relaxed ]] ;;
    VOXCMD_WAKE_PAUSE_FOR_MEDIA | VOXCMD_WAKE_PAUSE_FOR_MIC) [[ "$value" == 0 || "$value" == 1 ]] ;;
    *) return 0 ;;
  esac
}
