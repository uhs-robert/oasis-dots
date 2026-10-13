# shellcheck shell=bash
# The ways out of a voice mode, shared by the modes that are left by saying so (Click, Rapid, Type), sourced from
# "$voxcmd_share_dir". Each names its mode, since a bare "stop", "exit" or "close" is a button label or another command.

mode_exit_filler='(okay|ok|alright|please|now)'

# mode_exit_phrase <object regex>: "stop <object>", "<object> off" and the other verbs, with filler words around.
mode_exit_phrase() {
  local object="$1"
  printf '(%s )*((stop|exit|quit|end|leave|finish|close|turn off|switch off) %s|%s off)( %s)*' \
    "$mode_exit_filler" "$object" "$object" "$mode_exit_filler"
}
