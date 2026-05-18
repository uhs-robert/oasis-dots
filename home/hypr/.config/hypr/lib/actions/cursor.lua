--- Cursor actions: pointer movement, scrolling, clicking, key dispatch via wlrctl/hyprctl.

--- @class DirActions
--- @field left  function
--- @field right function
--- @field up    function
--- @field down  function

--- @class CursorActions
local Cursor = {}

--- Cursor movement factory for Direction.speed_binds.
--- @param amount number  Pixels to move per trigger
--- @return DirActions
function Cursor.move(amount)
  -- stylua: ignore
  return {
    left  = function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer move -" .. amount .. " 0")) end,
    right = function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer move "  .. amount .. " 0")) end,
    up    = function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer move 0 -" .. amount)) end,
    down  = function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer move 0 "  .. amount)) end,
  }
end

--- Scroll action factory. Returns up/down/left/right actions at the given step size.
--- @param step number
--- @return { up: fun(), down: fun(), left: fun(), right: fun() }
function Cursor.scroll(step)
  -- stylua: ignore
  return {
    up    = function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer scroll "  .. step .. " 0")) end,
    down  = function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer scroll -" .. step .. " 0")) end,
    left  = function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer scroll 0 -" .. step)) end,
    right = function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer scroll 0 "  .. step)) end,
  }
end

--- @return fun()
function Cursor.click_left()
  return function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer click left")) end
end

--- @return fun()
function Cursor.click_middle()
  return function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer click middle")) end
end

--- @return fun()
function Cursor.click_right()
  return function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer click right")) end
end

--- wl-kbptr mode commands by name.
local KBPTR_CMDS = {
  -- stylua: ignore
  floating_click = "wl-kbptr -o modes=floating,click -o mode_floating.source=detect",
  floating_move = "wl-kbptr -o modes=floating -o mode_floating.source=detect",
  tile_click = "wl-kbptr -o modes=tile,click",
  tile_move = "wl-kbptr -o modes=tile",
}

--- Run a wl-kbptr mode.
--- @param mode string  Key into KBPTR_CMDS
--- @return fun()
function Cursor.kbptr(mode)
  local cmd = assert(KBPTR_CMDS[mode], "unknown kbptr mode: " .. mode)
  return function() hl.dispatch(hl.dsp.exec_cmd(cmd)) end
end

--- Send a key shortcut to the active window via hyprctl sendshortcut.
--- @param key string  Key name, e.g. "LEFT", "prior", "next"
--- @return fun()
function Cursor.send_key(key)
    hl.dispatch(hl.dsp.exec_cmd("hyprctl dispatch sendshortcut , " .. key .. ", activewindow"))
  end
end

return Cursor
