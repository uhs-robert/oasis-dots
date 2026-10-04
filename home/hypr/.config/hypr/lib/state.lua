-- home/hypr/.config/hypr/lib/state.lua

--- Directory for this config's runtime state, honouring XDG_STATE_HOME.
--- @return string
return function()
  local xdg = os.getenv("XDG_STATE_HOME")
  return ((xdg and xdg ~= "") and xdg or (os.getenv("HOME") or "") .. "/.local/state") .. "/hypr"
end
