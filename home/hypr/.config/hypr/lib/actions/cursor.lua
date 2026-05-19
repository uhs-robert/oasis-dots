--- Cursor actions: pointer movement, scrolling, clicking, key dispatch via wlrctl/hyprctl.

local Hypr = require("lib.hypr") --- @class HyprLib

--- @class DirActions
--- @field left  function
--- @field right function
--- @field up    function
--- @field down  function

--- wl-kbptr mode commands by name.
local KBPTR_CMDS = {
  floating_click = "wl-kbptr -o modes=floating,click -o mode_floating.source=detect",
  floating_move = "wl-kbptr -o modes=floating -o mode_floating.source=detect",
  tile_click = "wl-kbptr -o modes=tile,click",
  tile_move = "wl-kbptr -o modes=tile",
}

--- @class CursorActions
local Cursor = {
  click_left = function() return Hypr.exec("wlrctl pointer click left") end,
  click_right = function() return Hypr.exec("wlrctl pointer click right") end,
  click_middle = function() return Hypr.exec("wlrctl pointer click middle") end,
}

--- Cursor movement factory for Direction.speed_binds.
--- @param amount number  Pixels to move per trigger
--- @return DirActions
Cursor.move = function(amount)
  return {
    left = Hypr.exec("wlrctl pointer move -" .. amount .. " 0"),
    right = Hypr.exec("wlrctl pointer move " .. amount .. " 0"),
    up = Hypr.exec("wlrctl pointer move 0 -" .. amount),
    down = Hypr.exec("wlrctl pointer move 0 " .. amount),
  }
end

--- Scroll action factory. Returns up/down/left/right actions at the given step size.
--- @param step number
--- @return { up: fun(), down: fun(), left: fun(), right: fun() }
Cursor.scroll = function(step)
  return {
    up = Hypr.exec("wlrctl pointer scroll " .. step .. " 0"),
    down = Hypr.exec("wlrctl pointer scroll -" .. step .. " 0"),
    left = Hypr.exec("wlrctl pointer scroll 0 -" .. step),
    right = Hypr.exec("wlrctl pointer scroll 0 " .. step),
  }
end

--- Run a wl-kbptr mode.
--- @param mode string  Key into KBPTR_CMDS
--- @return fun()
Cursor.kbptr = function(mode)
  local cmd = assert(KBPTR_CMDS[mode], "unknown kbptr mode: " .. mode)
  return Hypr.exec(cmd)
end

--- Send a key shortcut to the active window via hyprctl sendshortcut.
--- @param key string  Key name, e.g. "LEFT", "prior", "next"
--- @return fun()
Cursor.send_key = function(key) return Hypr.send(key) end

return Cursor
