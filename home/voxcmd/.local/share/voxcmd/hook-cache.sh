# shellcheck shell=bash
# Sourced by the keybinds.sh hook library: the on-disk cache of the list it builds. There is no TTL, since
# a stale list runs the wrong bind; the caller's key has to cover every input, this file's own mtime included
# (hook_cache_library). A cache that cannot be read or written is a miss and never an error.

voxcmd_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/voxcmd"
# shellcheck disable=SC2034 # read by the libraries that source this
hook_cache_library="${BASH_SOURCE[0]}"

# Prints the payload cached under the name when it was stored for this key, else fails. The key line first and the end
# marker last make a file that is foreign or cut short a miss.
cache_read() {
  local content
  { content=$(<"$voxcmd_cache_dir/$1"); } 2>/dev/null || return 1
  [[ "$content" == "$2"$'\n'*$'\n#end' ]] || return 1
  content=${content#"$2"$'\n'}
  content=${content%$'\n#end'}
  [ -z "$content" ] || printf '%s\n' "$content"
}

# Stores the payload under the name for the key. Written to a temp file in the same directory and renamed, so a
# concurrent reader sees the old file or the new one and never half of one. A hook that is killed between the two
# leaves its temp file behind (SIGKILL cannot be trapped), so each write sweeps the ones an hour old.
cache_write() {
  local temp="$voxcmd_cache_dir/.$1.$BASHPID.tmp"
  [ -d "$voxcmd_cache_dir" ] || mkdir -p "$voxcmd_cache_dir" 2>/dev/null || return 0
  { printf '%s\n%s\n#end\n' "$2" "$3" >"$temp" && mv -f "$temp" "$voxcmd_cache_dir/$1"; } 2>/dev/null || rm -f "$temp" 2>/dev/null
  find "$voxcmd_cache_dir" -maxdepth 1 -name '.*.tmp' -mmin +60 -delete 2>/dev/null
  return 0
}
