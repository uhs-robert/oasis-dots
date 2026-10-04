#!/bin/sh
# Runs luacheck on the Hyprland and greetd Lua; luacheck 1.2.0 cannot load under Lua 5.5, so fall back to an older interpreter.
set -u

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")
cd "$repo_dir" || exit 1

set -- home/hypr/.config/hypr system/etc/greetd

if command -v luacheck >/dev/null 2>&1 && luacheck --version >/dev/null 2>&1; then
  exec luacheck "$@"
fi

# Loads luacheck from source root $2 under interpreter $1, whose own luarocks tree supplies lfs.
run_with() {
  interp=$1
  root=$2
  shift 2
  lua_version=$("$interp" -e 'io.write((_VERSION:gsub("Lua ", "")))') || return 1
  rocks="$HOME/.luarocks"
  path="$rocks/share/lua/$lua_version/?.lua;$rocks/share/lua/$lua_version/?/init.lua;$root/?.lua;$root/?/init.lua;"
  cpath="$rocks/lib/lua/$lua_version/?.so;"
  printf 'require "luacheck.main"\n' |
    "$interp" -e "package.path = '$path' .. package.path; package.cpath = '$cpath' .. package.cpath" - "$@"
}

found=''
for main in "$HOME"/.luarocks/share/lua/*/luacheck/main.lua /usr/share/lua/*/luacheck/main.lua /usr/local/share/lua/*/luacheck/main.lua; do
  [ -f "$main" ] || continue
  found=1
  root=$(dirname -- "$(dirname -- "$main")")
  for interp in lua5.4 lua5.3 luajit lua5.1 lua; do
    command -v "$interp" >/dev/null 2>&1 || continue
    if run_with "$interp" "$root" --version >/dev/null 2>&1; then
      run_with "$interp" "$root" "$@"
      exit
    fi
  done
done

if [ -n "$found" ] || command -v luacheck >/dev/null 2>&1; then
  echo 'skip: luacheck needs Lua 5.1-5.4 with LuaFileSystem (luacheck package, or lua54 and lua54-filesystem)'
else
  echo 'skip: luacheck not installed'
fi
